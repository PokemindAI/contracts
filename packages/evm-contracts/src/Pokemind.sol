// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract Pokemind is ReentrancyGuard, Ownable, Pausable {
    // Constants
    uint256 public constant EPOCH_DURATION = 1 weeks;
    uint256 public constant MIN_STAKE = 100 * 1e18; // 100 POKE

    struct Pool {
        string pokemonName;
        bool isStarter;
        bool isActive;
        uint256 totalStaked;
        mapping(uint256 => uint256) rewardPerTokenStored; // rewardToken index -> amount
        mapping(uint256 => uint256) lastUpdateEpoch; // rewardToken index -> epoch
        mapping(uint256 => uint256) rewardRate; // rewardToken index -> rate
    }

    struct UserStake {
        uint256 amount;
        uint256 startEpoch;
        mapping(uint256 => uint256) rewards; // rewardToken index -> pending reward
        mapping(uint256 => uint256) userRewardPerTokenPaid; // rewardToken index -> last reward per token
    }

    struct PoolInfo {
        uint256 pokemonId;
        bool isStarter;
    }

    struct PoolView {
        uint256 pokemonId;
        string pokemonName;
        bool isStarter;
        bool isActive;
        uint256 totalStaked;
    }

    // State variables
    IERC20 public immutable pokeToken;
    IERC20[] public rewardTokens;
    uint256 public currentEpoch;
    uint256 public epochStartTime;
    uint256 public starterPoolsCount;
    uint256 public totalPoolsCount;

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => mapping(address => UserStake)) public userStakes;
    PoolInfo[] public activePools;
    mapping(uint256 => uint256) public poolIdToArrayIndex; // pokemonId => index in activePools

    // Events
    event PoolCreated(uint256 indexed poolId, string pokemonName, bool isStarter);
    event PoolDeactivated(uint256 indexed poolId);
    event PoolReactivated(uint256 indexed poolId);
    event Staked(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolId, uint256 amount);
    event RewardAdded(uint256 indexed poolId, uint256 indexed rewardTokenIndex, uint256 amount);
    event RewardClaimed(address indexed user, uint256 indexed poolId, uint256 indexed rewardTokenIndex, uint256 amount);
    event NewEpochStarted(uint256 indexed epochNumber, uint256 timestamp);
    event EmergencyWithdrawn(address indexed user, uint256 indexed poolId, uint256 amount);
    event RewardTokenAdded(address indexed token, uint256 indexed index);

    constructor(address _pokeToken) Ownable(msg.sender) {
        pokeToken = IERC20(_pokeToken);
        epochStartTime = block.timestamp;
        currentEpoch = 0;

        // Initialize starter pools
        createPokemonPool(1, "Bulbasaur", true);
        createPokemonPool(4, "Charmander", true);
        createPokemonPool(7, "Squirtle", true);
    }

    // Owner functions
    function addRewardToken(address _token) external onlyOwner {
        rewardTokens.push(IERC20(_token));
        emit RewardTokenAdded(_token, rewardTokens.length - 1);
    }

    function createPokemonPool(uint256 pokemonId, string memory pokemonName, bool isStarter) public onlyOwner {
        require(!pools[pokemonId].isActive, "Pool already exists");
        if (isStarter) {
            require(starterPoolsCount < 4, "Max starter pools reached"); // Pokemon Yellow sets the limit
            starterPoolsCount++;
        }

        Pool storage pool = pools[pokemonId];
        pool.pokemonName = pokemonName;
        pool.isStarter = isStarter;
        pool.isActive = true;
        totalPoolsCount++;

        // Add to active pools tracking
        poolIdToArrayIndex[pokemonId] = activePools.length;
        activePools.push(PoolInfo({ pokemonId: pokemonId, isStarter: isStarter }));

        emit PoolCreated(pokemonId, pokemonName, isStarter);
    }

    function deactivatePool(uint256 pokemonId) external onlyOwner {
        require(pools[pokemonId].isActive, "Pool not active");
        pools[pokemonId].isActive = false;

        // Remove from active pools
        uint256 indexToRemove = poolIdToArrayIndex[pokemonId];
        uint256 lastIndex = activePools.length - 1;

        if (indexToRemove != lastIndex) {
            PoolInfo memory lastPool = activePools[lastIndex];
            activePools[indexToRemove] = lastPool;
            poolIdToArrayIndex[lastPool.pokemonId] = indexToRemove;
        }

        activePools.pop();
        delete poolIdToArrayIndex[pokemonId];

        emit PoolDeactivated(pokemonId);
    }

    function reactivatePool(uint256 pokemonId) external onlyOwner {
        require(!pools[pokemonId].isActive, "Pool already active");
        Pool storage pool = pools[pokemonId];
        pool.isActive = true;

        // Add back to active pools
        poolIdToArrayIndex[pokemonId] = activePools.length;
        activePools.push(PoolInfo({ pokemonId: pokemonId, isStarter: pool.isStarter }));

        emit PoolReactivated(pokemonId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Core functions
    function stake(uint256 pokemonId, uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= MIN_STAKE, "Below minimum stake");
        require(pools[pokemonId].isActive, "Pool not active");

        updatePool(pokemonId);

        Pool storage pool = pools[pokemonId];
        UserStake storage userStake = userStakes[pokemonId][msg.sender];

        require(pokeToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        pool.totalStaked += amount;
        userStake.amount += amount;
        userStake.startEpoch = currentEpoch;

        emit Staked(msg.sender, pokemonId, amount);
    }

    function withdraw(uint256 pokemonId) external nonReentrant {
        require(isEpochComplete(), "Epoch not complete");
        require(pools[pokemonId].isActive, "Pool not active");

        updatePool(pokemonId);

        Pool storage pool = pools[pokemonId];
        UserStake storage userStake = userStakes[pokemonId][msg.sender];

        uint256 amount = userStake.amount;
        require(amount > 0, "No stake found");

        pool.totalStaked -= amount;
        userStake.amount = 0;

        require(pokeToken.transfer(msg.sender, amount), "Transfer failed");

        emit Withdrawn(msg.sender, pokemonId, amount);
    }

    function emergencyWithdraw(uint256 pokemonId) external nonReentrant {
        UserStake storage userStake = userStakes[pokemonId][msg.sender];
        uint256 amount = userStake.amount;
        require(amount > 0, "No stake found");

        Pool storage pool = pools[pokemonId];
        pool.totalStaked -= amount;
        userStake.amount = 0;

        // Reset rewards
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            userStake.rewards[i] = 0;
            userStake.userRewardPerTokenPaid[i] = 0;
        }

        require(pokeToken.transfer(msg.sender, amount), "Transfer failed");

        emit EmergencyWithdrawn(msg.sender, pokemonId, amount);
    }

    function addRewards(uint256 pokemonId, uint256 rewardTokenIndex, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        require(pools[pokemonId].isActive, "Pool not active");
        require(amount > 0, "Invalid amount");
        require(rewardTokenIndex < rewardTokens.length, "Invalid reward token");

        IERC20 rewardToken = rewardTokens[rewardTokenIndex];
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        Pool storage pool = pools[pokemonId];
        pool.rewardRate[rewardTokenIndex] = amount / EPOCH_DURATION;

        emit RewardAdded(pokemonId, rewardTokenIndex, amount);
    }

    function claimRewards(uint256 pokemonId) external nonReentrant whenNotPaused {
        require(pools[pokemonId].isActive, "Pool not active");

        updatePool(pokemonId);

        UserStake storage userStake = userStakes[pokemonId][msg.sender];

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 reward = pendingReward(pokemonId, msg.sender, i);
            if (reward > 0) {
                userStake.rewards[i] = 0;
                userStake.userRewardPerTokenPaid[i] = pools[pokemonId].rewardPerTokenStored[i]; // Add this line
                require(rewardTokens[i].transfer(msg.sender, reward), "Transfer failed");
                emit RewardClaimed(msg.sender, pokemonId, i, reward);
            }
        }
    }

    // View functions
    function pendingReward(uint256 pokemonId, address user, uint256 rewardTokenIndex) public view returns (uint256) {
        Pool storage pool = pools[pokemonId];
        UserStake storage userStake = userStakes[pokemonId][user];

        uint256 rewardPerToken = pool.rewardPerTokenStored[rewardTokenIndex];
        if (pool.totalStaked > 0) {
            uint256 timeSinceLastUpdate = block.timestamp - pool.lastUpdateEpoch[rewardTokenIndex];
            rewardPerToken += (timeSinceLastUpdate * pool.rewardRate[rewardTokenIndex] * 1e18) / pool.totalStaked;
        }

        return (userStake.amount * (rewardPerToken - userStake.userRewardPerTokenPaid[rewardTokenIndex])) / 1e18
            + userStake.rewards[rewardTokenIndex];
    }

    function getTopStarterChoice() external view returns (uint256 pokemonId, uint256 totalStaked) {
        uint256 highestStake = 0;
        uint256 chosenId = 0; // <-- This is the issue, we should initialize with the first starter

        for (uint256 i = 0; i < activePools.length; i++) {
            if (activePools[i].isStarter) {
                Pool storage pool = pools[activePools[i].pokemonId];
                // When stakes are equal, we should still pick a valid starter
                if (pool.totalStaked >= highestStake) {
                    // Changed from > to >=
                    highestStake = pool.totalStaked;
                    chosenId = activePools[i].pokemonId;
                }
            }
        }

        return (chosenId, highestStake);
    }

    function getTopTeamChoices() external view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory topIds = new uint256[](6);
        uint256[] memory topStakes = new uint256[](6);

        // Initialize with minimum values
        for (uint256 i = 0; i < 6; i++) {
            topStakes[i] = 0;
            topIds[i] = 0;
        }

        // Find top 6 non-starter pools
        for (uint256 i = 0; i < activePools.length; i++) {
            if (!activePools[i].isStarter) {
                Pool storage pool = pools[activePools[i].pokemonId];
                // Find position in top 6
                for (uint256 j = 0; j < 6; j++) {
                    if (pool.totalStaked > topStakes[j]) {
                        // Shift everything down
                        for (uint256 k = 5; k > j; k--) {
                            topIds[k] = topIds[k - 1];
                            topStakes[k] = topStakes[k - 1];
                        }
                        topIds[j] = activePools[i].pokemonId;
                        topStakes[j] = pool.totalStaked;
                        break;
                    }
                }
            }
        }

        return (topIds, topStakes);
    }

    function getUserStakeInfo(uint256 pokemonId, address user)
        external
        view
        returns (uint256 staked, uint256 startEpoch, uint256[] memory pendingRewards)
    {
        UserStake storage userStake = userStakes[pokemonId][user];
        pendingRewards = new uint256[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            pendingRewards[i] = pendingReward(pokemonId, user, i);
        }

        return (userStake.amount, userStake.startEpoch, pendingRewards);
    }

    function getActivePoolsInfo() external view returns (PoolView[] memory) {
        PoolView[] memory poolViews = new PoolView[](activePools.length);

        for (uint256 i = 0; i < activePools.length; i++) {
            uint256 pokemonId = activePools[i].pokemonId;
            Pool storage pool = pools[pokemonId];

            poolViews[i] = PoolView({
                pokemonId: pokemonId,
                pokemonName: pool.pokemonName,
                isStarter: pool.isStarter,
                isActive: pool.isActive,
                totalStaked: pool.totalStaked
            });
        }

        return poolViews;
    }

    function getRewardTokensCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    function getActivePoolsCount() external view returns (uint256) {
        return activePools.length;
    }

    // Internal functions
    function updatePool(uint256 pokemonId) internal {
        Pool storage pool = pools[pokemonId];
        UserStake storage userStake = userStakes[pokemonId][msg.sender];

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (pool.totalStaked == 0) {
                pool.lastUpdateEpoch[i] = block.timestamp;
                continue;
            }

            uint256 timeSinceLastUpdate = block.timestamp - pool.lastUpdateEpoch[i];
            if (timeSinceLastUpdate > 0) {
                pool.rewardPerTokenStored[i] += (timeSinceLastUpdate * pool.rewardRate[i] * 1e18) / pool.totalStaked;
                pool.lastUpdateEpoch[i] = block.timestamp;
            }

            uint256 pendingRewards =
                (userStake.amount * (pool.rewardPerTokenStored[i] - userStake.userRewardPerTokenPaid[i])) / 1e18;

            if (pendingRewards > 0) {
                userStake.rewards[i] += pendingRewards;
                userStake.userRewardPerTokenPaid[i] = pool.rewardPerTokenStored[i];
            }
        }
    }

    function isEpochComplete() public view returns (bool) {
        return block.timestamp >= epochStartTime + EPOCH_DURATION;
    }

    function startNewEpoch() external whenNotPaused {
        require(isEpochComplete(), "Current epoch not complete");
        currentEpoch++;
        epochStartTime = block.timestamp;
        emit NewEpochStarted(currentEpoch, block.timestamp);
    }

    // Recovery functions
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(pokeToken), "Cannot recover stake token");
        bool isRewardToken = false;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (address(rewardTokens[i]) == tokenAddress) {
                isRewardToken = true;
                break;
            }
        }
        require(!isRewardToken, "Cannot recover reward token");
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
    }
}
