// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {L1Read, L1Write} from "./libraries/HcorePrecompiles.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

/// @custom:oz-upgrades-from AlphaHYPEManager04
contract AlphaHYPEManager05 is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {

    // Constants
    address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
    uint256 constant SCALE_18_TO_8 = 10 ** 10;
    uint256 constant BPS_DENOMINATOR = 10_000; // 100% = 10_000 bps
    uint256 constant FEE_BPS = 10; // 0.1%

    // Structs
    struct DepositRequest {
        address depositor;
        uint256 amount;
    }

    struct WithdrawalRequestDeprecated {
        address withdrawer;
        uint256 amount;
    }

    struct WithdrawalRequest {
        address withdrawer;
        uint256 amount;
        uint256 pricePerTokenX18;
    }

    // Storage
    DepositRequest[] public depositQueue;
    WithdrawalRequestDeprecated[] public withdrawalQueue;
    uint256 public pendingDepositAmount; // Total amount of deposits that have been processed but not yet staked
    uint256 public withdrawalAmount;
    uint256 public owedUnderlyingAmount; // Total amount of withdrawals that have been requested but not yet processed
    uint256 public feeAmount; // Total fees collected

    address public validator;
    uint64 public hypeTokenIndex;
    uint64 public maxSupply; // 0 = no cap

    // Pull logic to prevent re-entrancy / DoS
    mapping(address => uint256) public owedUnderlyingAmounts;

    uint256 public lastProcessedBlock;
    uint256 public virtualWithdrawalAmount;
    WithdrawalRequest[] public pendingWithdrawalQueue;

    address public processor;
    uint256 public minDepositAmount;
    uint256 public lastBridgeEventBlock;

    uint256[44] private __gap;

    // Events
    event DepositQueued(address indexed depositor, uint256 amount);
    event DepositProcessed(address indexed depositor, uint256 amount, uint256 wrappedAmount);
    event WithdrawalQueued(address indexed withdrawer, uint256 wrappedAmount);
    event WithdrawalProcessed(address indexed withdrawer, uint256 amount, uint256 wrappedAmount);
    event WithdrawalClaimed(address indexed withdrawer, uint256 amount);

    event EVMSend(uint256 amount, address to);
    event SpotSend(uint256 amount, address to);
    event StakingDeposit(uint256 amount);
    event StakingWithdraw(uint256 amount);
    event TokenDelegate(address indexed validator, uint256 amount, bool isUndelegate);

    using SafeCast for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _validator, uint64 _hypeTokenIndex) external initializer {
        __ERC20_init("Alpha HYPE", unicode"αHYPE");
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        require(_validator != address(0), "AlphaHYPEManager: ZERO_ADDRESS");

        validator = _validator;
        hypeTokenIndex = _hypeTokenIndex;
    }

    // Handle native currency transfers
    receive() external payable {
        if (msg.sender == HYPE_SYSTEM_ADDRESS) {
            // Core → EVM bridge
        } else {
            // Handle user deposits
            _handleNativeTransfer(msg.sender, msg.value);
        }
    }

    fallback() external payable {
        if (msg.sender == HYPE_SYSTEM_ADDRESS) {
            // Core → EVM bridge
        } else {
            // Handle user deposits
            _handleNativeTransfer(msg.sender, msg.value);
        }
    }

    function pendingWithdrawalQueueLength() public view returns (uint256) {
        return pendingWithdrawalQueue.length;
    }

    function pendingDepositQueueLength() public view returns (uint256) {
        return depositQueue.length;
    }

    // Set decimals to 8
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function getERC20Supply() public view returns (uint256) {
        uint256 erc20Supply = totalSupply() + withdrawalAmount;
        return erc20Supply;
    }

    function getUnderlyingSupply() public view returns (uint256) {
        require(block.number != lastBridgeEventBlock, "AlphaHYPEManager: STALE_PRECOMPILE");

        // EVM balance
        uint256 underlyingSupply = (address(this).balance) / SCALE_18_TO_8 - pendingDepositAmount - owedUnderlyingAmount - feeAmount; // EVM balance in 8 decimals

        // Delegator balance
        L1Read.DelegatorSummary memory ds = L1Read.delegatorSummary(address(this));
        underlyingSupply += ds.delegated;
        underlyingSupply += ds.undelegated;
        underlyingSupply += ds.totalPendingWithdrawal;

        // Spot balance
        L1Read.SpotBalance memory sb = L1Read.spotBalance(address(this), hypeTokenIndex); // Assuming token index 1 for HYPE
        underlyingSupply += sb.total; // Assuming HYPE has 8 decimals

        return underlyingSupply;
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "AlphaHYPEManager: INVALID_AMOUNT");
        require(balanceOf(msg.sender) >= _amount, "AlphaHYPEManager: INSUFFICIENT_BALANCE");
        require(pendingWithdrawalQueue.length < 100, "AlphaHYPEManager: WITHDRAWAL_QUEUE_FULL");

        uint256 erc20Supply = getERC20Supply();
        uint256 underlyingSupply = getUnderlyingSupply();
        uint256 withdrawPricePerTokenX18;
        if (erc20Supply > 0) {
            // Calculate the price with additional precision to avoid rounding errors
            withdrawPricePerTokenX18 = Math.mulDiv(underlyingSupply, 1e18, erc20Supply, Math.Rounding.Floor);
        } else {
            withdrawPricePerTokenX18 = 10 ** 18; // Initial price is 1:1
        }

        // Add to withdrawal queue
        pendingWithdrawalQueue.push(WithdrawalRequest({withdrawer: msg.sender, amount: _amount, pricePerTokenX18: withdrawPricePerTokenX18}));

        // Burn wrapped tokens
        _burn(msg.sender, _amount);

        // Update total withdrawal amount
        withdrawalAmount += _amount;
        virtualWithdrawalAmount += Math.mulDiv(_amount, withdrawPricePerTokenX18, 1e18, Math.Rounding.Ceil);

        emit WithdrawalQueued(msg.sender, _amount);
    }

    // User claims their withdrawal
    function claimWithdrawal() external {
        uint256 amount = owedUnderlyingAmounts[msg.sender];
        require(amount > 0, "AlphaHYPEManager: NO_WITHDRAWAL");
        owedUnderlyingAmounts[msg.sender] = 0; // Update state first (checks-effects-interactions)
        owedUnderlyingAmount -= amount; // Decrement total owed amount
        uint256 amountWei = amount * SCALE_18_TO_8;
        (bool success,) = payable(msg.sender).call{value: amountWei}("");
        require(success, "AlphaHYPEManager: CLAIM_FAILED"); // Safe to revert here; only affects caller
        emit WithdrawalClaimed(msg.sender, amountWei);
    }

    function processQueues() external nonReentrant {
        require(lastProcessedBlock < block.number, "AlphaHYPEManager: ALREADY_PROCESSED");
        if (processor != address(0)) {
            require(processor == msg.sender, "AlphaHYPEManager: PROCESSOR_ONLY");
        }
        lastProcessedBlock = block.number;
        uint256 evmHype8 = address(this).balance / SCALE_18_TO_8;
        require(evmHype8 >= owedUnderlyingAmount + pendingDepositAmount + feeAmount, "AlphaHYPEManager: BANKRUPT");

        uint256 underlyingSupply = evmHype8 - pendingDepositAmount - owedUnderlyingAmount - feeAmount; // EVM balance in 8 decimals

        // Delegator balance
        L1Read.DelegatorSummary memory ds = L1Read.delegatorSummary(address(this));
        // Those three can never overflow uint64 because that's the max value on HyperCore
        underlyingSupply += (ds.delegated + ds.undelegated + ds.totalPendingWithdrawal);

        // Spot balance
        L1Read.SpotBalance memory sb = L1Read.spotBalance(address(this), hypeTokenIndex); // Assuming token index 1 for HYPE
        underlyingSupply += sb.total; // Assuming HYPE has 8 decimals

        // Impossible to overflow uint64 with current supply of HYPE
        require(underlyingSupply + pendingDepositAmount < type(uint64).max, "AlphaHYPEManager: BALANCE_OVERFLOW");

        uint256 erc20Supply = getERC20Supply();

        // Calculate price per token: underlyingSupply / totalSupply (HYPE per aHYPE)
        // If no tokens exist yet, use 1:1 ratio
        uint256 depositPricePerTokenX18;
        uint256 withdrawPricePerTokenX18;
        if (erc20Supply > 0) {
            // Calculate the price with additional precision to avoid rounding errors
            depositPricePerTokenX18 = Math.mulDiv(underlyingSupply, 1e18, erc20Supply, Math.Rounding.Ceil);
            withdrawPricePerTokenX18 = Math.mulDiv(underlyingSupply, 1e18, erc20Supply, Math.Rounding.Floor);
        } else {
            depositPricePerTokenX18 = 10 ** 18; // Initial price is 1:1
            withdrawPricePerTokenX18 = 10 ** 18; // Initial price is 1:1
        }

        // Process deposits
        _processDeposits(depositPricePerTokenX18);

        // Process withdrawals
        _processWithdrawals(withdrawPricePerTokenX18);

        uint256 _virtualWithdrawalAmount = Math.mulDiv(withdrawalAmount, withdrawPricePerTokenX18, 1e18, Math.Rounding.Ceil);
        // _virtualWithdrawalAmount can over-estimate the amount of HYPE requested for withdrawals
        if (_virtualWithdrawalAmount > virtualWithdrawalAmount) {
            _virtualWithdrawalAmount = virtualWithdrawalAmount;
        }

        evmHype8 = address(this).balance / SCALE_18_TO_8;

        require(evmHype8 >= owedUnderlyingAmount + pendingDepositAmount + feeAmount, "AlphaHYPEManager: BANKRUPT");
        evmHype8 -= owedUnderlyingAmount + pendingDepositAmount + feeAmount;

        if (_virtualWithdrawalAmount > evmHype8) {
            _virtualWithdrawalAmount -= evmHype8;
            // First, check spot balance
            uint256 toBridgeToEVM = Math.min(sb.total, _virtualWithdrawalAmount);
            if (toBridgeToEVM > 0) {
                L1Write.spotSend(HYPE_SYSTEM_ADDRESS, hypeTokenIndex, toBridgeToEVM);
                emit SpotSend(toBridgeToEVM, HYPE_SYSTEM_ADDRESS);
                lastBridgeEventBlock = block.number;
                _virtualWithdrawalAmount -= toBridgeToEVM;
            }
            // Then, check pending withdrawals
            if (ds.totalPendingWithdrawal < _virtualWithdrawalAmount) {
                // Pending withdrawal doesn't cover withdrawal amount
                _virtualWithdrawalAmount -= ds.totalPendingWithdrawal;
                uint256 toWithdrawFromStaking = Math.min(ds.undelegated, _virtualWithdrawalAmount);
                if (toWithdrawFromStaking > 0) {
                    L1Write.stakingWithdraw(toWithdrawFromStaking.toUint64());
                    emit StakingWithdraw(toWithdrawFromStaking);
                    _virtualWithdrawalAmount -= toWithdrawFromStaking;
                }
                // Not enough pending withdrawals to cover the withdrawals, we need to undelegate the rest
                uint256 toUndelegate = Math.min(ds.delegated, _virtualWithdrawalAmount);
                if (toUndelegate > 0) {
                    L1Write.tokenDelegate(validator, toUndelegate, true);
                    emit TokenDelegate(validator, toUndelegate, true);
                }
            } else {
                // We have enough pending withdrawals, just can't process them yet
            }
        } else {
            // Send all remaining to staking
            if (evmHype8 > 0) {
                uint256 toSendWei = Math.mulDiv(evmHype8, SCALE_18_TO_8, 1);
                (bool success,) = payable(HYPE_SYSTEM_ADDRESS).call{value: toSendWei}("");
                require(success, "Failed to send HYPE to spot");
                emit EVMSend(evmHype8, HYPE_SYSTEM_ADDRESS);
                lastBridgeEventBlock = block.number;
            }
            if (sb.total > 0) {
                L1Write.stakingDeposit(sb.total);
                emit StakingDeposit(sb.total);
            }
            if (ds.undelegated > 0) {
                L1Write.tokenDelegate(validator, ds.undelegated, false);
                emit TokenDelegate(validator, ds.undelegated, false);
            }
        }
    }

    function collectFees() external onlyOwner {
        require(feeAmount > 0, "AlphaHYPEManager: NO_FEES");
        uint256 amountWei = feeAmount * SCALE_18_TO_8;
        feeAmount = 0; // Update state first (checks-effects-interactions)
        (bool success,) = payable(msg.sender).call{value: amountWei}("");
        require(success, "AlphaHYPEManager: COLLECT_FAILED");
    }

    function setMaxSupply(uint64 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        minDepositAmount = _minDepositAmount;
    }

    function setProcessor(address _processor) external onlyOwner {
        processor = _processor;
    }

    function _handleNativeTransfer(address from, uint256 value) internal {
        require(msg.value >= minDepositAmount, "AlphaHYPEManager: AMOUNT_TOO_SMALL");
        require(depositQueue.length < 100, "AlphaHYPEManager: DEPOSIT_QUEUE_FULL");
        // Require amount to be multiple of 10^10 to avoid rounding issues
        require(value % (10 ** 10) == 0, "AlphaHYPEManager: INVALID_AMOUNT");
        uint256 amount = value / (10 ** 10); // Work in 8 decimals
        require(amount < type(uint64).max, "AlphaHYPEManager: AMOUNT_TOO_LARGE");

        // Supply cap for safety (0 = no cap)
        // We approximate underlying supply with ERC20 supply to avoid calling core precompiles
        if (maxSupply > 0) {
            require(totalSupply() + amount + pendingDepositAmount <= maxSupply, "AlphaHYPEManager: MAX_SUPPLY_EXCEEDED");
        }

        // Add to deposit queue
        depositQueue.push(DepositRequest({depositor: from, amount: amount}));

        // Update total deposit amount for correct accounting
        pendingDepositAmount += amount;

        emit DepositQueued(from, amount);
    }

    function _processDeposits(uint256 _pricePerTokenX18) internal {
        for (uint256 i = 0; i < depositQueue.length; i++) {
            DepositRequest memory request = depositQueue[i];

            // Calculate amount of wrapped tokens to mint: HYPE amount / price per token
            // HYPE / (HYPE / aHYPE) = aHYPE
            uint256 mintFee = Math.mulDiv(request.amount, FEE_BPS, BPS_DENOMINATOR, Math.Rounding.Ceil);
            uint256 wrappedAmount = Math.mulDiv(request.amount - mintFee, 1e18, _pricePerTokenX18, Math.Rounding.Floor);

            // Mint wrapped tokens
            _mint(request.depositor, wrappedAmount);

            // Solidity handles underflow
            pendingDepositAmount -= request.amount;
            feeAmount += mintFee;

            emit DepositProcessed(request.depositor, request.amount, wrappedAmount);
        }

        // Clear deposit queue
        if (depositQueue.length > 0) {
            delete depositQueue;
        }
    }

    function _processWithdrawals(uint256 _pricePerTokenX18) internal {
        uint256 hypeBalance = (address(this).balance / SCALE_18_TO_8) - feeAmount - owedUnderlyingAmount; // Convert wei to 8 decimals
        uint256 processedCount = 0;

        for (uint256 i = 0; i < pendingWithdrawalQueue.length && hypeBalance > 0; i++) {
            WithdrawalRequest memory request = pendingWithdrawalQueue[i];

            uint256 withdrawPricePerTokenX18 = request.pricePerTokenX18;
            // If withdrawal price is higher than the current price, use the current price
            // Because this means the validator got slashed and the withdrawer should be penalized
            if (withdrawPricePerTokenX18 == 0 || withdrawPricePerTokenX18 > _pricePerTokenX18) {
                withdrawPricePerTokenX18 = _pricePerTokenX18;
            }
            // aHYPE * (HYPE / aHYPE) = HYPE (gross)
            uint256 hypeGross = Math.mulDiv(request.amount, withdrawPricePerTokenX18, 1e18, Math.Rounding.Floor);
            // Apply 0.1% burn fee on underlying payout
            uint256 burnFee = Math.mulDiv(hypeGross, FEE_BPS, BPS_DENOMINATOR, Math.Rounding.Ceil);
            uint256 hypeAmount = hypeGross - burnFee;

            // Process withdrawal if we have enough HYPE
            if (hypeGross <= hypeBalance) {
                // hypeAmount goes to user
                owedUnderlyingAmounts[request.withdrawer] += hypeAmount;
                owedUnderlyingAmount += hypeAmount;
                // burnFee goes to protocol
                feeAmount += burnFee;

                hypeBalance -= hypeGross;
                processedCount++;
                // Solidity handles underflow
                withdrawalAmount -= request.amount; // Decrement total withdrawal amount
                virtualWithdrawalAmount -= Math.mulDiv(request.amount, request.pricePerTokenX18, 1e18, Math.Rounding.Ceil);

                emit WithdrawalProcessed(request.withdrawer, hypeAmount, request.amount);
            } else {
                // Not enough HYPE, keep this withdrawal and all the ones remaining in the queue
                break;
            }
        }

        // Remove processed withdrawals from queue
        if (processedCount > 0) {
            // Shift remaining elements to the beginning
            for (uint256 i = 0; i < pendingWithdrawalQueue.length - processedCount; i++) {
                pendingWithdrawalQueue[i] = pendingWithdrawalQueue[i + processedCount];
            }

            // Resize the array
            for (uint256 i = 0; i < processedCount; i++) {
                pendingWithdrawalQueue.pop();
            }
        }
    }
}
