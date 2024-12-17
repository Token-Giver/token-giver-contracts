// *************************************************************************
//                            ERRORS
// *************************************************************************
pub mod Errors {
    pub const NOT_CAMPAIGN_OWNER: felt252 = 'TGN: not campaign owner!';
    pub const ALREADY_MINTED: felt252 = 'TGN: user already minted!';
    pub const INITIALIZED: felt252 = 'TGN: already initialized!';
    pub const INVALID_OWNER: felt252 = 'TGN: caller is not owner!';
    pub const INVALID_CAMPAIGN: felt252 = 'TGN: campaign is not owner!';
    pub const INSUFFICIENT_BALANCE: felt252 = 'TGN: insufficient balance!';
    pub const TRANSFER_FAILED: felt252 = 'TGN: transfer failed!';
}
