use starknet::ContractAddress;

// *************************************************************************
//                              INTERFACE of LOCK
// *************************************************************************

#[starknet::interface]
pub trait ICampaignLock<TState> {
    fn lock(ref self: TState, lock_util:u64);
}