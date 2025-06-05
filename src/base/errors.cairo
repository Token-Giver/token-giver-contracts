// *************************************************************************
//                            ERRORS
// *************************************************************************
pub mod Errors {
    pub const NOT_CAMPAIGN_OWNER: felt252 = 'TGN: not campaign owner!';
    pub const NOT_CONTRACT_OWNER: felt252 = 'TGN: not contract owner!';
    pub const ALREADY_MINTED: felt252 = 'TGN: user already minted!';
    pub const INITIALIZED: felt252 = 'TGN: already initialized!';
    pub const INVALID_OWNER: felt252 = 'TGN: caller is not owner!';
    pub const INVALID_CAMPAIGN: felt252 = 'TGN: campaign is not owner!';
    pub const INSUFFICIENT_BALANCE: felt252 = 'TGN: insufficient balance!';
    pub const TRANSFER_FAILED: felt252 = 'TGN: transfer failed!';
    pub const INVALID_CAMPAIGN_ADDRESS: felt252 = 'TGN: invalid campaign address!';
    pub const INVALID_POOL_ADDRESS: felt252 = 'TGN: invalid pool address!';
    pub const INVALID_AMOUNT: felt252 = 'TGN: invalid amount!';
    pub const ZERO_ADDRESS: felt252 = 'TGN: zero address not allowed';
    pub const INVALID_REGISTRY_HASH: felt252 = 'TGN: invalid registry hash';
    pub const INVALID_IMPLEMENTATION_HASH: felt252 = 'TGN: invalid impl hash';
    pub const CAMPAIGN_POOL_EXISTS: felt252 = 'TGN: campaign pool exists';
    pub const MAX_POOLS_EXCEEDED: felt252 = 'TGN: max pools exceeded';
}
