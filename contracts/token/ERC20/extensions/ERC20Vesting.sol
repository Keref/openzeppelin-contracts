// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {ERC20} from "../ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to vest tokens before withdraw
 * Useful in combination with ERC20Wrapper for locking up tokens
 * Default vesting schedule is linear
 * A user can have multiple vesting schedules
 */
abstract contract ERC20Vesting is ERC20 {
  /// Event: Vesting
  event Vested(address indexed user, uint256 amount);
  /// Event: update vesting duration
  event UpdatedVestingDuration(uint vestingDuration);
  /// Event: Send tokens to user while penalty for early unlock is burnt
  event Withdraw(address indexed user, uint256 received, uint256 penalty);

  /// @notice vesting duration in seconds
  uint256 private _vestingDuration; 

  /// @notice Token vesting structure
  struct VestingSchedule {
    uint128 vestedAmount;
    uint64 startTime;
    // Rserved data field for user defined logic
    uint64 data;
  }

  /// @notice Vesting schedule
  mapping(address => VestingSchedule[]) private _vestingSchedules;

  /// @notice Total vesting tokens
  uint256 private _totalVestingBalance;

  /// @notice Individual allocation vesting amount
  mapping(address => uint256) private _userVestingBalances;
  
  
  
  /// @dev Sets the the value for {vestingDuration}
  constructor(uint256 vestingDuration_){
    require(vestingDuration_ > 0, "ERC20Vesting: Zero vesting");
    _vestingDuration = vestingDuration_;
  }
  
  //////// GETTERS
  
  /// @notice Returns the vesting duration
  function vestingDuration() public view returns (uint256){
    return _vestingDuration;
  }
  
  /// @notice Returns total amount currently vesting
  function totalVestingBalance() public view returns (uint256) {
    return _totalVestingBalance;
  }
  
  /// @notice Returns the currently vesting balance for user
  function vestingBalanceOf(address user) public view returns (uint256) {
    return _userVestingBalances[user];
  }
  
  /// @notice Get number of vesting structs for a user
  function getVestingLength(address user) public view returns (uint256) {
    return _vestingSchedules[user].length;
  }
  
  /// @notice Returns data for a given schedule
  function getVestingSchedule(address user, uint vestingId) 
    public view returns (uint256 vestedAmount, uint256 startTime, uint64 data)
  {
    VestingSchedule memory vs = _vestingSchedules[user][vestingId];
    return (uint256(vs.vestedAmount), uint256(vs.startTime), vs.data);
  }
  
  /// @notice Update vesting duration
  /// @param vestingDuration_ New vesting duration, non infinite
  function _updateVestingDuration(uint256 vestingDuration_) internal virtual {
    require(vestingDuration_ > 0 && vestingDuration_ < 2**64, "Invalid vesting duration");
    _vestingDuration = vestingDuration_;
    emit UpdatedVestingDuration(_vestingDuration);
  }  
  
  
  //////// VESTING LOGIC
  
  /// @notice Vest locked token
  /// @param vestingAmount Amount of tokens to vest
  function vest(uint vestingAmount) public virtual {
    address sender = _msgSender();
    require(balanceOf(sender) >= vestingAmount + vestingBalanceOf(sender), "ERC20Vesting: Insufficient Balance to Vest");
    uint64 data;
    _vest(sender, vestingAmount, data);
  }
  
  
  /// @notice Vesting starts the unlock countdown for a user's subset of tokens
  /// @dev Caller should make sure that the user has enough funds to vest
  function _vest(address user, uint256 vestingAmount, uint64 data) internal {
    require(vestingAmount > 0 || vestingAmount < type(uint224).max, "ERC20Vesting: Invalid vesting amount");
    _vestingSchedules[user].push(VestingSchedule(uint128(vestingAmount), uint64(block.timestamp), data));
    _totalVestingBalance += vestingAmount;
    _userVestingBalances[user] += vestingAmount;
    emit Vested(user, vestingAmount);
  }
  
  
  /// @notice User can withdraw tokens once vesting is over
  /// @param user Owner of the vesting structure
  /// @param vestingId Id of the vesting structure since each user can have several
  /// @return received Amount of tokens unlocked to send to the user
  /// @return penalty Amount of tokens to burn as early withdrawal penalty
  /// @dev Doesnt actually send anything, only does accounting and return values to be sent/burnt - doesn't check ownership
  function _withdraw(address user, uint256 vestingId) internal returns (uint256 received, uint256 penalty){
    uint userVestingLength = getVestingLength(user);
    require(userVestingLength > vestingId, "Invalid vestingId");

    uint64 startTime = _vestingSchedules[user][vestingId].startTime;
    uint256 vestedAmount = uint256(_vestingSchedules[user][vestingId].vestedAmount);
    
    (received, penalty) = vestingSchedule(vestedAmount, startTime);

    // remove struct from list
    if(vestingId < userVestingLength - 1){
      _vestingSchedules[user][vestingId] = _vestingSchedules[user][userVestingLength - 1];
    }
    _vestingSchedules[user].pop();
    
    _totalVestingBalance -= uint256(vestedAmount);
    _userVestingBalances[user] -= uint256(vestedAmount);
    emit Withdraw(user, received, penalty);
  }
  
  
  /// @notice Calculates the amount that can be received
  /// @param vestedAmount Amount of tokens vested
  /// @param startTime End of vesting timestamp
  /// @return received Amount of tokens unlocked to send to the user
  /// @return remaining Amount of tokens remaining locked
  /// @dev Two simple use cases: withdrawal forbidden if remaining > 0, or remaining is burnt when early unlock
  function vestingSchedule(uint256 vestedAmount, uint64 startTime) public view returns (uint256 received, uint256 remaining) {
    if (block.timestamp >= startTime + _vestingDuration){
      received = vestedAmount;
    }
    else if (block.timestamp <= startTime){
      remaining = vestedAmount;
    }
    else {
      (received, remaining) = _vestingSchedule(vestedAmount, startTime);
    }
  }
  
  
  /// @notice Calculate the actual received/penalty amounts for non trivial results, default is linear unlock
  function _vestingSchedule(uint256 vestedAmount, uint64 startTime) internal view virtual returns (uint256 received, uint256 remaining) {
    received = (vestedAmount * (block.timestamp - startTime)) / _vestingDuration;
    remaining = vestedAmount - received;
  }
  
  
  //////// OVERRIDES
  
}