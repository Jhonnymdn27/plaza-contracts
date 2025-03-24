// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Pool} from "./Pool.sol";
import {BondToken} from "./BondToken.sol";
import {PoolFactory} from "./PoolFactory.sol";
import {LeverageToken} from "./LeverageToken.sol";
import {BalancerOracleAdapter} from "./BalancerOracleAdapter.sol";
import {
  IManagedPoolFactory, ManagedPoolParams, ManagedPoolSettingsParams
} from "./lib/balancer/IManagedPoolFactory.sol";
import {IManagedPool} from "./lib/balancer/IManagedPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IVault} from "@balancer/contracts/interfaces/contracts/vault/IVault.sol";
import {IAsset} from "@balancer/contracts/interfaces/contracts/vault/IAsset.sol";

contract PreDeposit is Initializable, ReentrancyGuardUpgradeable, UUPSUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;

  bytes32 public constant ROYCO_ROLE = keccak256("ROYCO_ROLE");
  address public constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  uint256 private constant BALANCER_MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%, enforced by Balancer

  // Initializing pool params
  address public pool;
  PoolFactory private factory;
  PoolFactory.PoolParams private params;
  BalancerOracleAdapter public balancerOracleAdapter;
  IManagedPoolFactory public balancerManagedPoolFactory;
  IVault public balancerVault;

  uint256 public depositCap;

  uint256 private bondAmount;
  uint256 private leverageAmount;
  string private bondName;
  string private bondSymbol;
  string private leverageName;
  string private leverageSymbol;

  uint256 public depositStartTime;
  uint256 public depositEndTime;

  bool public poolCreated;

  uint256 public nAllowedTokens;
  uint256 public snapshotCapValue;
  mapping(address => bool) public isAllowedToken;
  mapping(uint256 => address) public allowedTokens;
  mapping(address => uint256) public tokenSnapshotPrices;
  address[] public rejectedTokens;

  // Deposit balances
  mapping(address => mapping(address => uint256)) public balances; // user => token => amount

  // Events
  event PoolCreated(address indexed pool);
  event BalancerPoolCreated(address indexed balancerPool);
  event DepositCapIncreased(uint256 newReserveCap);
  event Deposited(address indexed user, address[] tokens, uint256[] amounts);
  event Withdrawn(address indexed user, address[] tokens, uint256[] amounts);
  event Claimed(address indexed user, uint256 bondAmount, uint256 leverageAmount);
  event InitialPoolWeights(uint256[] weights);
  event TokenExcluded(address token);

  // Errors
  error AccessDenied();
  error DepositEnded();
  error NothingToClaim();
  error DepositNotEnded();
  error NoReserveAmount();
  error CapMustIncrease();
  error DepositCapReached();
  error InsufficientBalance();
  error InvalidReserveToken();
  error DepositNotYetStarted();
  error DepositAlreadyStarted();
  error ClaimPeriodNotStarted();
  error DepositEndMustBeAfterStart();
  error InvalidBondOrLeverageAmount();
  error DepositEndMustOnlyBeExtended();
  error DepositStartMustOnlyBeExtended();
  error PoolAlreadyCreated();
  error NoTokenValue();
  error InvalidArrayLengths();
  error DepositEndedAndPoolNotCreated();
  error InsufficientAllowance();
  error InsufficientBondAllowance();
  error InsufficientLeverageAllowance();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initializes the contract with pool parameters and configuration.
   * @param _params Pool parameters struct
   * @param _factory Address of the pool factory
   * @param _depositStartTime Start time for deposits
   * @param _depositEndTime End time for deposits
   * @param _depositCap Maximum deposit amount
   * @param _bondName Name of the bond token
   * @param _bondSymbol Symbol of the bond token
   * @param _leverageName Name of the leverage token
   * @param _leverageSymbol Symbol of the leverage token
   */
  function initialize(
    PoolFactory.PoolParams memory _params,
    address _factory,
    address _balancerManagedPoolFactory,
    address _balancerVault,
    address _balancerOracleAdapter,
    uint256 _depositStartTime,
    uint256 _depositEndTime,
    uint256 _depositCap,
    address[] memory _allowedTokens,
    string memory _bondName,
    string memory _bondSymbol,
    string memory _leverageName,
    string memory _leverageSymbol
  ) public initializer {
    __UUPSUpgradeable_init();
    __ReentrancyGuard_init();
    params = _params;
    depositStartTime = _depositStartTime;
    depositEndTime = _depositEndTime;
    depositCap = _depositCap;
    factory = PoolFactory(_factory);
    balancerManagedPoolFactory = IManagedPoolFactory(_balancerManagedPoolFactory);
    balancerVault = IVault(_balancerVault);
    balancerOracleAdapter = BalancerOracleAdapter(_balancerOracleAdapter);
    bondName = _bondName;
    bondSymbol = _bondSymbol;
    leverageName = _leverageName;
    leverageSymbol = _leverageSymbol;
    poolCreated = false;

    _allowedTokens = _sortAddresses(_allowedTokens);

    for (uint256 i = 0; i < _allowedTokens.length; i++) {
      isAllowedToken[_allowedTokens[i]] = true;
      allowedTokens[i] = _allowedTokens[i];
    }
    nAllowedTokens = _allowedTokens.length;
  }

  function deposit(address token, uint256 amount, address onBehalfOf) external nonReentrant whenNotPaused {
    address[] memory tokens = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    tokens[0] = token;
    amounts[0] = amount;

    _deposit(tokens, amounts, onBehalfOf);
  }

  function deposit(address token, uint256 amount) external nonReentrant whenNotPaused {
    address[] memory tokens = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    tokens[0] = token;
    amounts[0] = amount;

    _deposit(tokens, amounts, msg.sender);
  }

  function deposit(address[] memory tokens, uint256[] memory amounts, address onBehalfOf)
    external
    nonReentrant
    whenNotPaused
  {
    _deposit(tokens, amounts, onBehalfOf);
  }

  function deposit(address[] memory tokens, uint256[] memory amounts) external nonReentrant whenNotPaused {
    _deposit(tokens, amounts, msg.sender);
  }

  function _deposit(address[] memory tokens, uint256[] memory amounts, address recipient)
    private
    checkDepositStarted
    checkDepositNotEnded
  {
    _checkArrayLengths(tokens, amounts);
    _checkCap(tokens, amounts);

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
      address token = tokens[i];
      uint256 amount = amounts[i];
      balances[recipient][token] += amount;
    }

    emit Deposited(recipient, tokens, amounts);
  }

  function withdrawTo(address from, address to, address token, uint256 amount)
    external
    nonReentrant
    whenNotPaused
    checkDepositEndedAndPoolNotCreated
  {
    if (IERC20(token).allowance(from, to) < amount) revert InsufficientAllowance();

    address[] memory tokens = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    tokens[0] = token;
    amounts[0] = amount;

    _withdraw(from, to, tokens, amounts);
  }

  function withdraw(address token, uint256 amount)
    external
    nonReentrant
    whenNotPaused
    checkDepositEndedAndPoolNotCreated
  {
    address[] memory tokens = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    tokens[0] = token;
    amounts[0] = amount;

    _withdraw(msg.sender, msg.sender, tokens, amounts);
  }

  function withdraw(address[] memory tokens, uint256[] memory amounts)
    external
    nonReentrant
    whenNotPaused
    checkDepositEndedAndPoolNotCreated
  {
    _withdraw(msg.sender, msg.sender, tokens, amounts);
  }

  function _withdraw(address owner, address userTo, address[] memory tokens, uint256[] memory amounts) private {
    _checkArrayLengths(tokens, amounts);

    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      uint256 amount = amounts[i];
      if (balances[owner][token] < amount) revert InsufficientBalance();
      balances[owner][token] -= amount;
      IERC20(token).safeTransfer(userTo, amount);
    }

    emit Withdrawn(owner, tokens, amounts);
  }

  /**
   * @dev
   * First creates a new managed Balancer pool
   * then joins the Balancer pool
   * then finally creates a new plaza pool
   *
   * User shares are calculated based on the value of their deposit at the time of pool creation
   */
  function createPool(bytes32 salt) external nonReentrant whenNotPaused checkDepositEnded {
    IAsset[] memory tokens = new IAsset[](nAllowedTokens);
    uint256[] memory amounts = new uint256[](nAllowedTokens);
    uint256[] memory normalizedWeights = new uint256[](nAllowedTokens);

    uint256 _snapshotCapValue = currentPredepositTotal();
    snapshotCapValue = _snapshotCapValue;

    if (poolCreated) revert PoolAlreadyCreated();
    if (_snapshotCapValue == 0) revert NoReserveAmount();
    if (bondAmount == 0 || leverageAmount == 0) revert InvalidBondOrLeverageAmount();

    for (uint256 i = 0; i < nAllowedTokens; i++) {
      tokens[i] = IAsset(allowedTokens[i]);
      amounts[i] = IERC20(allowedTokens[i]).balanceOf(address(this));

      // Fetch the prices and store in snapshot. We calculate user shares based on value at pool
      // creation time
      uint256 tokenPrice = balancerOracleAdapter.getOraclePrice(address(tokens[i]), ETH);
      tokenSnapshotPrices[address(tokens[i])] = tokenPrice;

      // Determine the normalized weights of the tokens based on the balances of each token
      // Done by calculating the ratio in terms of number of tokens * price of token in terms of ETH
      normalizedWeights[i] = amounts[i] * tokenPrice / _snapshotCapValue;

      IERC20(address(tokens[i])).approve(address(balancerVault), amounts[i]);
    }

    (normalizedWeights, tokens, amounts) = _validateNormalizedWeights(normalizedWeights);

    // Create a new managed Balancer pool
    address[] memory assetManagers = new address[](nAllowedTokens);
    ManagedPoolParams memory balancerPoolParams =
      ManagedPoolParams({name: "Plaza Eth Balancer Pool", symbol: "PLAZA-ETH-BLP", assetManagers: assetManagers});

    ManagedPoolSettingsParams memory balancerPoolSettingsParams = ManagedPoolSettingsParams({
      tokens: tokens,
      normalizedWeights: normalizedWeights,
      swapFeePercentage: BALANCER_MIN_SWAP_FEE_PERCENTAGE,
      swapEnabledOnStart: true,
      mustAllowlistLPs: false,
      managementAumFeePercentage: 0,
      aumFeeId: 0
    });

    IERC20 balancerPoolToken = IERC20(
      balancerManagedPoolFactory.create(
        balancerPoolParams, balancerPoolSettingsParams, PoolFactory(factory).governance(), salt
      )
    );

    // Join Balancer pool
    bytes memory userData = abi.encode(0, amounts); // amounts in userData does not include lp token
    amounts = _prependUint256Max(amounts);
    tokens = _prependLpToken(tokens, address(balancerPoolToken));
    IVault.JoinPoolRequest memory request =
      IVault.JoinPoolRequest({assets: tokens, maxAmountsIn: amounts, userData: userData, fromInternalBalance: false});

    balancerVault.joinPool(IManagedPool(address(balancerPoolToken)).getPoolId(), address(this), address(this), request);
    uint256 reserveAmount = balancerPoolToken.balanceOf(address(this));
    params.reserveToken = address(balancerPoolToken);

    balancerPoolToken.approve(address(factory), reserveAmount);
    pool = factory.createPool(
      params, reserveAmount, bondAmount, leverageAmount, bondName, bondSymbol, leverageName, leverageSymbol, true
    );

    emit InitialPoolWeights(normalizedWeights);
    emit BalancerPoolCreated(address(balancerPoolToken));
    emit PoolCreated(pool);
    poolCreated = true;
  }

  /**
   * @dev Allows users to claim their share of bond and leverage tokens after pool creation.
   */
  function claim() external nonReentrant whenNotPaused checkDepositEnded {
    if (pool == address(0)) revert ClaimPeriodNotStarted();

    (uint256 bondClaimableAmount, uint256 leverageClaimableAmount) = _getClaimableAmount(msg.sender);
    if (bondClaimableAmount == 0 && leverageClaimableAmount == 0) revert NothingToClaim();

    _claim(msg.sender, msg.sender, bondClaimableAmount, leverageClaimableAmount);
  }

  function claimTo(address from, address to) external nonReentrant whenNotPaused checkDepositEnded {
    if (pool == address(0)) revert ClaimPeriodNotStarted();

    address bondToken = address(Pool(pool).bondToken());
    address leverageToken = address(Pool(pool).lToken());

    (uint256 bondClaimableAmount, uint256 leverageClaimableAmount) = _getClaimableAmount(from);

    if (IERC20(bondToken).allowance(from, to) < bondClaimableAmount && !factory.hasRole(ROYCO_ROLE, msg.sender)) {
      revert InsufficientBondAllowance();
    }
    if (IERC20(leverageToken).allowance(from, to) < leverageClaimableAmount && !factory.hasRole(ROYCO_ROLE, msg.sender))
    {
      revert InsufficientLeverageAllowance();
    }

    _claim(from, to, bondClaimableAmount, leverageClaimableAmount);
  }

  function _getClaimableAmount(address user) public view returns (uint256, uint256) {
    // Cleaner to just bruteforce check user's contribution for each whitelisted token
    uint256 userValueContribution;
    for (uint256 i = 0; i < nAllowedTokens; i++) {
      address token = allowedTokens[i];
      uint256 userTokenBalance = balances[user][token];
      if (userTokenBalance > 0) userValueContribution += (userTokenBalance * tokenSnapshotPrices[token]);
    }

    userValueContribution = userValueContribution / 1e18;

    if (userValueContribution == 0) return (0, 0);

    uint256 userBondShare = (bondAmount * userValueContribution) / snapshotCapValue;
    uint256 userLeverageShare = (leverageAmount * userValueContribution) / snapshotCapValue;

    return (userBondShare, userLeverageShare);
  }

  function _claim(address owner, address userTo, uint256 userBondShare, uint256 userLeverageShare) private {
    for (uint256 i = 0; i < nAllowedTokens; i++) {
      balances[owner][allowedTokens[i]] = 0;
    }

    address bondToken = address(Pool(pool).bondToken());
    address leverageToken = address(Pool(pool).lToken());

    if (userBondShare > 0) IERC20(bondToken).safeTransfer(userTo, userBondShare);

    if (userLeverageShare > 0) IERC20(leverageToken).safeTransfer(userTo, userLeverageShare);

    emit Claimed(owner, userBondShare, userLeverageShare);
  }

  /**
   * @dev Updates pool parameters. Can only be called by owner before deposit end time.
   * @param _params New pool parameters
   */
  function setParams(PoolFactory.PoolParams memory _params) external onlyRole(factory.GOV_ROLE()) checkDepositNotEnded {
    if (poolCreated) revert PoolAlreadyCreated();

    params = _params;
  }

  /**
   * @dev Sets the bond and leverage token amounts. Can only be called by owner before deposit end
   * time.
   * @param _bondAmount Amount of bond tokens
   * @param _leverageAmount Amount of leverage tokens
   */
  function setBondAndLeverageAmount(uint256 _bondAmount, uint256 _leverageAmount)
    external
    onlyRole(factory.GOV_ROLE())
    checkDepositEnded
  {
    if (poolCreated) revert PoolAlreadyCreated();

    bondAmount = _bondAmount;
    leverageAmount = _leverageAmount;
  }

  /**
   * @dev Increases the reserve cap. Can only be called by owner before deposit end time.
   * @param newDepositCap New maximum deposit amount
   */
  function increaseDepositCap(uint256 newDepositCap) external onlyRole(factory.GOV_ROLE()) checkDepositNotEnded {
    if (newDepositCap <= depositCap) revert CapMustIncrease();
    if (poolCreated) revert PoolAlreadyCreated();
    depositCap = newDepositCap;

    emit DepositCapIncreased(newDepositCap);
  }

  /**
   * @dev Updates the deposit start time. Can only be called by owner before current start time.
   * @param newDepositStartTime New deposit start timestamp
   */
  function setDepositStartTime(uint256 newDepositStartTime) external onlyRole(factory.GOV_ROLE()) {
    if (block.timestamp >= depositStartTime) revert DepositAlreadyStarted();
    if (newDepositStartTime <= depositStartTime) revert DepositStartMustOnlyBeExtended();
    if (newDepositStartTime >= depositEndTime) revert DepositEndMustBeAfterStart();

    depositStartTime = newDepositStartTime;
  }

  /**
   * @dev Updates the deposit end time. Can only be called by owner before current end time.
   * @param newDepositEndTime New deposit end timestamp
   */
  function setDepositEndTime(uint256 newDepositEndTime) external onlyRole(factory.GOV_ROLE()) checkDepositNotEnded {
    if (newDepositEndTime <= depositEndTime) revert DepositEndMustOnlyBeExtended();
    if (newDepositEndTime <= depositStartTime) revert DepositEndMustBeAfterStart();
    if (poolCreated) revert PoolAlreadyCreated();

    depositEndTime = newDepositEndTime;
  }

  /**
   * @dev Returns the current deposit amount in terms of ETH.
   * @return The current deposit amount in ETH
   */
  function currentPredepositTotal() public view returns (uint256) {
    uint256 totalValue;
    for (uint256 i = 0; i < nAllowedTokens; i++) {
      address token = allowedTokens[i];
      uint256 price = balancerOracleAdapter.getOraclePrice(token, ETH);
      totalValue += (IERC20(token).balanceOf(address(this)) * price);
    }
    return totalValue / 1e18;
  }

  function getAllowedTokens() external view returns (address[] memory) {
    address[] memory tokens = new address[](nAllowedTokens);
    for (uint256 i = 0; i < nAllowedTokens; i++) {
      tokens[i] = allowedTokens[i];
    }
    return tokens;
  }

  function getNumbRejectedTokens() external view returns (uint256) {
    return rejectedTokens.length;
  }

  /**
   * @dev Checks if the deposit cap is reached. Taking a portion of the user deposit if the full
   * amount would exceed the
   * cap leads to other issues such as determining which of the token amounts can fit inside cap,
   * users preferred token
   * to be taken etc. Better to handle amounts and cap checks from frontend.
   * @param tokens Array of tokens to check
   * @param amounts Array of amounts to check
   */
  function _checkCap(address[] memory tokens, uint256[] memory amounts) private view {
    uint256 totalUserDepositValue;
    for (uint256 i = 0; i < tokens.length; i++) {
      address token = tokens[i];
      _checkTokenAllowed(token);
      uint256 price = balancerOracleAdapter.getOraclePrice(token, ETH);
      uint256 tokenDepositValue = (amounts[i] * price);
      if (tokenDepositValue == 0) revert NoTokenValue();
      totalUserDepositValue += tokenDepositValue;
    }

    totalUserDepositValue = totalUserDepositValue / 1e18;

    if (totalUserDepositValue + currentPredepositTotal() > depositCap) revert DepositCapReached();
  }

  function _checkTokenAllowed(address token) private view {
    if (!isAllowedToken[token]) revert InvalidReserveToken();
  }

  /**
   * @dev Validates the normalized weights of the tokens to ensure that the sum is 1e18.
   * @param normalizedWeights Array of normalized weights
   * @return Validated array of normalized weights
   */
  function _validateNormalizedWeights(uint256[] memory normalizedWeights)
    private
    returns (uint256[] memory, IAsset[] memory, uint256[] memory)
  {
    uint256 MIN_WEIGHT = 1e16; // 1%

    // First pass: count valid tokens and sum their weights
    uint256 validTokenCount = 0;
    uint256 totalValidWeight = 0;
    bool[] memory isValid = new bool[](normalizedWeights.length);

    for (uint256 i = 0; i < normalizedWeights.length; i++) {
      if (normalizedWeights[i] >= MIN_WEIGHT) {
        isValid[i] = true;
        validTokenCount++;
        totalValidWeight += normalizedWeights[i];
      } else {
        isAllowedToken[allowedTokens[i]] = false;
        rejectedTokens.push(allowedTokens[i]);
        emit TokenExcluded(allowedTokens[i]);
      }
    }

    // Create new arrays for valid tokens and weights
    uint256[] memory validatedWeights = new uint256[](validTokenCount);
    address[] memory validTokens = new address[](validTokenCount);
    uint256 validIndex = 0;

    // Second pass: normalize weights and update token array
    for (uint256 i = 0; i < normalizedWeights.length; i++) {
      if (isValid[i]) {
        // Normalize weight relative to total valid weight
        validatedWeights[validIndex] = (normalizedWeights[i] * 1e18) / totalValidWeight;
        validTokens[validIndex] = allowedTokens[i];
        validIndex++;
      }
    }

    // Ensure total weight is exactly 1e18
    uint256 totalWeight = 0;
    for (uint256 i = 0; i < validatedWeights.length; i++) {
      totalWeight += validatedWeights[i];
    }

    // Add or remove weight from largest weight if needed
    if (totalWeight > 1e18) validatedWeights[_getLargestIndex(validatedWeights)] -= totalWeight - 1e18; // Remove excess
      // weight

    else if (totalWeight < 1e18) validatedWeights[_getLargestIndex(validatedWeights)] += 1e18 - totalWeight; // Add
      // missing
      // weight

    // Update contract state to reflect removed tokens
    if (validTokenCount < nAllowedTokens) {
      nAllowedTokens = validTokenCount;
      for (uint256 i = 0; i < validTokenCount; i++) {
        allowedTokens[i] = validTokens[i];
      }

      snapshotCapValue = currentPredepositTotal();
    }

    // Return updated valid tokens, amounts, and weights
    // Inefficiently copies arrays even if no tokens are excluded
    IAsset[] memory validAssets = new IAsset[](validTokenCount);
    uint256[] memory validAmounts = new uint256[](validTokenCount);
    for (uint256 i = 0; i < validTokenCount; i++) {
      validAssets[i] = IAsset(validTokens[i]);
      validAmounts[i] = IERC20(validTokens[i]).balanceOf(address(this));
    }

    return (validatedWeights, validAssets, validAmounts);
  }

  /**
   * @dev Prepends a uint256 max value to the array of amounts. BalancerV2 uses the lptoken itself
   * as the first asset
   * @param amounts Array of amounts
   * @return Array of amounts with a uint256 max value at the beginning
   */
  function _prependUint256Max(uint256[] memory amounts) public pure returns (uint256[] memory) {
    uint256[] memory newAmounts = new uint256[](amounts.length + 1);
    newAmounts[0] = type(uint256).max;

    for (uint256 i = 0; i < amounts.length; i++) {
      newAmounts[i + 1] = amounts[i];
    }

    return newAmounts;
  }

  /**
   * @dev Prepends an lp token to the array of tokens.
   * @param tokens Array of tokens
   * @param lpToken Address of the lp token
   * @return Array of tokens with the lp token at the beginning
   */
  function _prependLpToken(IAsset[] memory tokens, address lpToken) public pure returns (IAsset[] memory) {
    IAsset[] memory newTokens = new IAsset[](tokens.length + 1);
    newTokens[0] = IAsset(lpToken);
    for (uint256 i = 0; i < tokens.length; i++) {
      newTokens[i + 1] = tokens[i];
    }
    return newTokens;
  }

  /**
   * @dev Sorts the addresses in ascending order.
   * @param addresses Array of addresses to sort
   * @return Sorted array of addresses
   */
  function _sortAddresses(address[] memory addresses) private pure returns (address[] memory) {
    for (uint256 i = 0; i < addresses.length; i++) {
      for (uint256 j = i + 1; j < addresses.length; j++) {
        if (addresses[i] > addresses[j]) (addresses[i], addresses[j]) = (addresses[j], addresses[i]);
      }
    }
    return addresses;
  }

  function _getLargestIndex(uint256[] memory values) private pure returns (uint256) {
    uint256 largestIndex = 0;
    for (uint256 i = 1; i < values.length; i++) {
      if (values[i] > values[largestIndex]) largestIndex = i;
    }
    return largestIndex;
  }

  function _checkArrayLengths(address[] memory tokens, uint256[] memory amounts) private pure {
    if (tokens.length != amounts.length) revert InvalidArrayLengths();
  }

  /**
   * @dev Pauses the contract. Reverts any interaction except upgrade.
   */
  function pause() external onlyRole(factory.SECURITY_COUNCIL_ROLE()) {
    _pause();
  }

  /**
   * @dev Unpauses the contract.
   */
  function unpause() external onlyRole(factory.SECURITY_COUNCIL_ROLE()) {
    _unpause();
  }

  /**
   * @dev Authorizes an upgrade to a new implementation.
   * Can only be called by the owner of the contract.
   * @param newImplementation The address of the new implementation.
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(factory.GOV_ROLE()) {}

  /**
   * @dev Modifier to check if the caller has the specified role.
   * @param role The role to check for.
   */
  modifier onlyRole(bytes32 role) {
    if (!factory.hasRole(role, msg.sender)) revert AccessDenied();
    _;
  }

  modifier checkDepositNotEnded() {
    if (block.timestamp >= depositEndTime) revert DepositEnded();
    _;
  }

  modifier checkDepositStarted() {
    if (block.timestamp < depositStartTime) revert DepositNotYetStarted();
    _;
  }

  modifier checkDepositEnded() {
    if (block.timestamp < depositEndTime) revert DepositNotEnded();
    _;
  }

  modifier checkDepositEndedAndPoolNotCreated() {
    if (block.timestamp >= depositEndTime && !poolCreated) revert DepositEndedAndPoolNotCreated();
    _;
  }
}
