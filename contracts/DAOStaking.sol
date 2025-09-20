//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

uint constant PERCENT_DECIMALS = 4;
uint constant PERCENT_PRECISION = 10**4;
uint constant MONTH_SECONDS = 3600 * 24 * 30;
uint constant YEAR_SECONDS = MONTH_SECONDS * 12;

/// @notice Staking variant structure
struct StakeVariant {
    /// @notice Months of tokens lock
    uint8 months;
    /// @notice Account votes multiplies with 4 decimals (10000 = 100%)
    uint24 votesMultiplier;
    /// @notice APY with 4 decimals (10000 = 100%);
    uint24 yearRewardMultiplier;
}

/// @notice Staking position structure
struct Stake {
    /// @notice Staking position index
    uint256 index;
    /// @notice Months of tokens lock / Staking variant
    uint8 months;
    /// @notice Locked tokens
    uint256 tokenAmount;
    /// @notice Staking date timestamp
    uint256 lockTimestamp;
}

/// @title DAOStaking
/// @notice Staking for determining shares in the DAO
contract DAOStaking is AccessControl {

    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice The ERC20 token used for mining rewards (immutable).
    IERC20 immutable public token;

    /// @notice Staking months set
    EnumerableSet.UintSet private _months;
    /// @notice Staking variants according to the months
    mapping(uint8 months => StakeVariant variant) private _variants;

    /// @notice Counter for staking indexes
    uint256 private _lockCounter;
    /// @notice Stake positions according to months of lock
    mapping(uint8 months => EnumerableSet.UintSet index) private _stakesIndexes;
    /// @notice Stake positions according to account
    mapping(address account => EnumerableSet.UintSet index) private _accountStakes;
    /// @notice Stake positions according to index
    mapping(uint256 index => Stake) private _stakePositions;

    /// @notice Pool of tokens locked by accounts
    uint private _commonTokensLocked;
    /// @notice Total number of votes
    uint public commonVotes;
    /// @notice Votes amounts according to accounts
    mapping(address account => uint256 votes) public accountVotes;

    constructor(address tokenAddress, address adminAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));

        token = IERC20(tokenAddress);
        /// No lock staking variant with x0.1 votes multiplier and 8% APY
        addStakingVariant(0, 1000, 800);
        /// 1 month lock staking variant with x0.25 votes multiplier and 24% APY
        addStakingVariant(1, 2500, 2400);
        /// 3 months lock staking variant with x0.75 votes multiplier and 36% APY
        addStakingVariant(3, 7500, 3600);
        /// 6 months lock staking variant with x1.5 votes multiplier and 50% APY
        addStakingVariant(6, 15000, 5000);
        /// 9 months lock staking variant with x1.75 votes multiplier and 64% APY
        addStakingVariant(9, 17500, 6400);
        /// 12 months lock staking variant with x3 votes multiplier and 88% APY
        addStakingVariant(12, 30000, 8800);
        /// 24 months lock staking variant with x5 votes multiplier and 108% APY
        addStakingVariant(24, 50000, 10800);
        /// 36 months lock staking variant with x7 votes multiplier and 148% APY
        addStakingVariant(36, 70000, 14800);

        _grantRole(DEFAULT_ADMIN_ROLE, adminAddress);
        _revokeRole(DEFAULT_ADMIN_ROLE, address(this));
        _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }


    /// Events

    event StakingVariantAdded(uint8 indexed months, uint24 votesMultiplier, uint24 yearRewardMultiplier);
    event StakingVariantEdited(uint8 indexed months, uint24 votesMultiplier, uint24 yearRewardMultiplier);
    event StakingVariandRemoved(uint8 indexed months);

    event Staked(address indexed account, uint8 indexed months, uint256 tokenAmount, uint256 rewardAmount, uint256 lockAmount, uint256 votesAmount, uint256 lockTimestamp);
    event Unstaked(address indexed account, uint8 indexed months, uint256 tokenAmount, uint256 rewardAmount, uint256 transferAmount, uint256 votesAmount, uint256 lockTimestamp, uint256 unlockTimestamp);

    event Withdraw(address indexed account, uint256 tokenAmount);


    /// Custom errors

    /// @dev Not enough tokens in reward pool
    /// @param available Available tokens in the reward pool
    /// @param needed Needed tokens for the future reward
    error NotEnoughTokensForReward(uint256 available, uint256 needed);

    /// @dev The lock period is not over yet
    /// @param currentTimestamp Current block timestamp
    /// @param unlockTimestamp Timestamp when unlock will be available
    error LockPeriodError(uint256 currentTimestamp, uint256 unlockTimestamp);


    /// Internal methods

    function _getVotesAmount(uint8 months, uint256 tokenAmount) internal view returns (uint256) {
        return tokenAmount * _variants[months].votesMultiplier / PERCENT_PRECISION;
    }

    function _getRewardSize(uint8 months, uint256 tokenAmount, uint256 lockTimestamp) internal view returns (uint256) {
        uint256 yearReward = tokenAmount * _variants[months].yearRewardMultiplier / PERCENT_PRECISION;
        if (months > 0) {
            return yearReward * months / 12;
        } else {
            uint256 time = block.timestamp - lockTimestamp;
            return yearReward * time / YEAR_SECONDS;
        }
    }

    function _getUnlockTimestamp(uint8 months, uint256 lockTimestamp) internal pure returns (uint256) {
        return lockTimestamp + months * MONTH_SECONDS;
    }


    /// Admin methods
    
    /// @notice Add a new stacking variant.
    /// @param months Lock period in months (255 max).
    /// @param votesMultiplier Votes multiplier with 4 decimals (10000 = 100%).
    /// @param yearRewardMultiplier Year reward with 4 decimals (10000 = 100%).
    /// @dev The caller must have DEFAULT_ADMIN_ROLE role.
    function addStakingVariant(uint8 months, uint24 votesMultiplier, uint24 yearRewardMultiplier)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!_months.contains(months), "This lock period is already exists");

        _months.add(months);
        _variants[months] = StakeVariant(
            months,
            votesMultiplier,
            yearRewardMultiplier
        );

        emit StakingVariantAdded(months, votesMultiplier, yearRewardMultiplier);
    }

    /// @notice Edit existing stacking variant.
    /// @param months Lock period in months (255 max).
    /// @param votesMultiplier Votes multiplier with 4 decimals (10000 = 100%).
    /// @param yearRewardMultiplier Year reward with 4 decimals (10000 = 100%).
    /// @dev The caller must have DEFAULT_ADMIN_ROLE role.
    function editStakingVariant(uint8 months, uint24 votesMultiplier, uint24 yearRewardMultiplier)
    public
    onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_months.contains(months), "This lock period is not exists");
        require(_stakesIndexes[months].length() == 0, "This lock period already in use");

        _variants[months].votesMultiplier = votesMultiplier;
        _variants[months].yearRewardMultiplier = yearRewardMultiplier;

        emit StakingVariantEdited(months, votesMultiplier, yearRewardMultiplier);
    }

    /// @notice Removes existing staking variant.
    /// @param months Lock period in months (255 max).
    /// @dev The caller must have DEFAULT_ADMIN_ROLE role.
    function removeStakingVariant(uint8 months)
    public
    onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_months.contains(months), "This lock period is not exists");
        require(_stakesIndexes[months].length() == 0, "This lock period already in use");

        _months.remove(months);

        emit StakingVariandRemoved(months);
    }

    /// @notice Withdraws free funds not reserved by staking.
    /// @param tokenAmount Amount of tokens to withdraw.
    /// @dev The caller must have DEFAULT_ADMIN_ROLE role.
    function withdraw(uint256 tokenAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(getAvailablePoolBalance() >= tokenAmount, "Not enough tokens in reward pool");

        token.transfer(_msgSender(), tokenAmount);
        
        emit Withdraw(_msgSender(), tokenAmount);
    }


    /// Public read methods

    /// @notice Returns the amount of tokens reserved by participants.
    /// @return Current pool balance locked by staking.
    function getLockedPoolBalance() public view returns (uint256) {
        return _commonTokensLocked;
    }

    /// @notice Tokens in the current pool balance released from locking.
    /// @return Available tokens for use.
    function getAvailablePoolBalance() public view returns (uint256) {
        return token.balanceOf(address(this)) - getLockedPoolBalance();
    }

    /// @notice Returns account share in the DAO
    /// @param account Account address
    /// @return Share percents with 4 decimals (10000 = 100%)
    function getAccountShare(address account) public view returns(uint24) {
        return uint24(accountVotes[account] * PERCENT_PRECISION / commonVotes);
    }

    /// @notice Returns amount of account staking positions
    /// @param account Account address
    /// @return Account staking positions array length
    function getAccountStakesLength(address account) public view returns(uint256) {
        return _accountStakes[account].length();
    }

    /// @notice Returns account staking positions
    /// @param account Account address
    /// @param offset Offset from the beginning of the array
    /// @param limit Number of positions to return
    /// @return Array of account staking positions
    /// @dev Limit can be greater than account stakes length
    function getAccountStakes(address account, uint256 offset, uint256 limit) public view returns(Stake[] memory) {
        uint256 available = _accountStakes[account].length();
        uint256 realLimit = offset > available
            ? 0
            : available - offset;
        if (limit < realLimit) {
            realLimit = limit;
        }
        Stake[] memory locks = new Stake[](realLimit);
        for (uint256 i = offset; i < offset + realLimit; i++) {
            locks[i] = _stakePositions[_accountStakes[account].at(i)];
        }
        return locks;
    }

    /// @notice Returns staking positions according to staking variant
    /// @param months Staking variant months
    /// @param offset Offset from the beginning of the array
    /// @param limit Number of positions to return
    /// @return Array of account staking positions
    function getVariantStakes(uint8 months, uint256 offset, uint256 limit) public view returns(Stake[] memory) {
        uint256 available = _stakesIndexes[months].length();
        uint256 realLimit = offset > available
            ? 0
            : available - offset;
        if (limit < realLimit) {
            realLimit = limit;
        }
        Stake[] memory locks = new Stake[](realLimit);
        for (uint256 i = offset; i < offset + realLimit; i++) {
            locks[i] = _stakePositions[_stakesIndexes[months].at(i)];
        }
        return locks;
    }

    /// @notice Returns staking variants
    /// @return Array of staking variants
    function getStakeVariants() public view returns(StakeVariant[] memory) {
        StakeVariant[] memory variants = new StakeVariant[](_months.length());
        for (uint256 i; i < variants.length; i++) {
            uint8 month = uint8(_months.at(i));
            variants[i] = _variants[month];
        }
        return variants;
    }


    /// Common write methods

    /// @notice Stake specified amount of tokens for a specified number of months.
    /// @param months Number of months of staking, from the list of staking variants.
    /// @param tokenAmount Amount of ERC20 tokens.
    /// @return Stacking index.
    function stake(uint8 months, uint256 tokenAmount) public returns (uint256) {
        address account = _msgSender();
        require(_months.contains(months), "This lock period is not exists");
        /// Transfer account tokens to the pool.
        require(token.transferFrom(account, address(this), tokenAmount), "Can't transfer token");

        /// Get future reward size and check reward pool.
        uint256 rewardSize = _getRewardSize(months, tokenAmount, block.timestamp);
        uint256 tokensToLock = tokenAmount + rewardSize;
        if (getAvailablePoolBalance() < tokensToLock) {
            revert NotEnoughTokensForReward(
                getAvailablePoolBalance() - tokenAmount,
                rewardSize
            );
        }
        _commonTokensLocked += tokensToLock;

        /// Increase votes pool.
        uint256 votes = _getVotesAmount(months, tokenAmount);
        accountVotes[account] += votes;
        commonVotes += votes;

        /// Create lock record.
        uint256 index = _lockCounter++;
        _stakesIndexes[months].add(index);
        _accountStakes[account].add(index);
        _stakePositions[index] = Stake(
            index,
            months,
            tokenAmount,
            block.timestamp
        );

        emit Staked(account, months, tokenAmount, rewardSize, tokensToLock, votes, block.timestamp);
        return index;
    }

    /// @notice Returns tokens from staking with rewards.
    /// @param index Staking index.
    /// @dev The caller must be the stake owner.
    function unstake(uint256 index) public {
        address account = _msgSender();
        require(_accountStakes[account].contains(index), "You have no access to this position or position is not exists");
        Stake storage data = _stakePositions[index];
        uint256 unlockTimestamp = _getUnlockTimestamp(data.months, data.lockTimestamp);
        if (block.timestamp < unlockTimestamp) {
            revert LockPeriodError(block.timestamp, unlockTimestamp);
        }

        uint256 rewardSize = _getRewardSize(data.months, data.tokenAmount, data.lockTimestamp);
        uint256 votes = _getVotesAmount(data.months, data.tokenAmount);

        /// Transfer tokens from the pool.
        uint256 amountToTransfer = data.tokenAmount + rewardSize;
        if (data.months > 0) {
            require(token.transfer(account, amountToTransfer), "Can't transfer token");
            _commonTokensLocked -= amountToTransfer;
        } else {
            uint256 available = getAvailablePoolBalance();
            if (available < rewardSize) {
                revert NotEnoughTokensForReward(available, rewardSize);
            }
            require(token.transfer(account, amountToTransfer), "Can't transfer token");
            _commonTokensLocked -= data.tokenAmount;
        }

        /// Decrease votes pool.
        accountVotes[account] -= votes;
        commonVotes -= votes;

        /// Remove account tokens lock.
        _stakesIndexes[data.months].remove(index);
        _accountStakes[account].remove(index);

        emit Unstaked(account, data.months, data.tokenAmount, rewardSize, amountToTransfer, votes, data.lockTimestamp, block.timestamp);
    }

    /// @notice Returns tokens from all available caller stakings
    function unstakeAvailable() public {
        address account = _msgSender();
        for (uint256 i; i < _accountStakes[account].length(); i++) {
            uint256 index = _accountStakes[account].at(i);
            if (_getUnlockTimestamp(_stakePositions[index].months, _stakePositions[index].lockTimestamp) >= block.timestamp) {
                unstake(index);
            }
        }
    }
    
}