// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20, IERC20} from "../../token/ERC20/ERC20.sol";
import {ERC20Vesting} from "../../token/ERC20/extensions/ERC20Vesting.sol";
import {ERC20Wrapper} from "../../token/ERC20/extensions/ERC20Wrapper.sol";
import {ERC20Votes} from "../../token/ERC20/extensions/ERC20Votes.sol";
import {SafeERC20} from "../../token/ERC20/utils/SafeERC20.sol";


// Escrowed governance requires vesting before withdrawal
abstract contract EsGovernanceTokenMock is ERC20Votes, ERC20Wrapper, ERC20Vesting {
  constructor(address token, uint64 vestingDuration) 
    ERC20Vesting(vestingDuration)
  {}

  
  // Withdrawal: ERC20Wrapper param {value} becomes a user schedule, amount withdrawn is defined by the schedule
  function withdrawTo(address account, uint256 userVestingId) public virtual override returns (bool) {
    //uint256 userVestingId = value;
    (uint256 unlockedAmount, uint256 lockedAmount) = _withdraw(account, userVestingId);
    require(lockedAmount == 0, "EsGovernanceTokenMock: Still Vesting");
    
    return super.withdrawTo(account, unlockedAmount);
  }
  
  // overrides
  function _update(address from, address to, uint256 value) internal virtual override (ERC20Votes, ERC20) {
    return super._update(from, to, value);
  }
  function decimals() public view virtual override (ERC20Wrapper, ERC20) returns (uint8) {
    return super.decimals();
  }
  function transfer(address to, uint256 value) public override (ERC20Vesting, ERC20) returns (bool) {
    return super.transfer(to, value);
  }
}



/** ve- kind of lockup model can lock tokens for 1w to 4y to get extra weight
 * token balance is the virtual balance. real balance of underlying is stored in _realBalances
 *
 * the weight is MIN_LOCKUP / MAX_LOCKUP * lockupDuration (e.g lock 1000 CRV for 4y: get 1000 veCRV, for 1w: get 1000*1/208 = ~4.8 veCRV)
 * Note that this is not the CRV model since durations cannot be extended or averaged etc.
 */
abstract contract VeGovernanceTokenMock is ERC20Votes, ERC20Vesting {
  IERC20 public immutable underlying;

  // Min and max lockup duration in seconds
  uint64 public constant MAX_LOCKUP = 4 * 365 * 86400; // ~4y
  uint64 public constant MIN_LOCKUP = 7 * 86400; // 1w
  
  // Token deposits are automatically vested, the real deposit balance is stored in an array indexed by the vesting structure id
  mapping (uint256 => uint256) public vestingUnderlyingBalances;
  
  
  constructor(address underlying_)
    ERC20Vesting(MAX_LOCKUP)
  {
    require(underlying_ != address(0x0), "VeGovernanceTokenMock: Invalid Underlying");
    underlying = IERC20(underlying_);
  }
  
  
  // Withdraws fully vested tokens
  function withdrawTo(address account, uint256 userVestingId) public returns (bool) {
    (uint256 unlockedAmount, uint256 lockedAmount) = _withdraw(account, userVestingId);
    require(lockedAmount == 0, "VeGovernanceTokenMock: Still Vesting");
    
    // Burn the virtual balance and withdraw the real underlying balance
    _burn(account, unlockedAmount);
    uint vestingId = getVestingScheduleId(account, userVestingId);
    SafeERC20.safeTransfer(underlying, account, vestingUnderlyingBalances[vestingId]);
  }
  
  
  // Deposit tokens: automatically starts vesting them
  function depositFor(address account, uint256 value, uint64 lockupDuration) public returns (bool) {
    require(lockupDuration >= MIN_LOCKUP && lockupDuration <= MAX_LOCKUP, "VeGovernanceTokenMock: Invalid Lockup Duration");
    
    uint weightedValue = value * lockupDuration * MIN_LOCKUP / MAX_LOCKUP;
    // Transfer underlying and mint virtual balance
    SafeERC20.safeTransferFrom(underlying, account, address(this), value);
    _mint(account, weightedValue);
    // automatically start vesting for lockupDuration
    uint vestingId = _vest(_msgSender(), value, uint64(block.timestamp + lockupDuration - MAX_LOCKUP));
    vestingUnderlyingBalances[vestingId] = value;
    
    return true;
  }
  
  
  // overrides
  function _update(address from, address to, uint256 value) internal virtual override (ERC20Votes, ERC20) {
    return super._update(from, to, value);
  }
  function transfer(address to, uint256 value) public override (ERC20Vesting, ERC20) returns (bool) {
    return super.transfer(to, value);
  }
}


/**
 * Liquidity mining vested rewards
 * Rewards are deposited in this contract and users can withdraw them after vesting 90d
 * Rewards can be withdrawn early, in which case there is a penalty and the non unlocked amount is burnt
 */
abstract contract VestedMiningRewardsMock is ERC20Vesting {
  IERC20 public immutable rewardToken;
  
  constructor(address rewardToken_) 
    ERC20Vesting(90 * 86400)
  {
    rewardToken = IERC20(rewardToken_);
  }
  
  
  function redeem(uint userVestingId) public returns (bool) {
    (uint256 unlockedAmount, uint256 lockedAmount) = _withdraw(msg.sender, userVestingId);
    // locked amount is ignored and lost, unlocked amount is transferred
    SafeERC20.safeTransfer(rewardToken, msg.sender, unlockedAmount);
  }
  
}