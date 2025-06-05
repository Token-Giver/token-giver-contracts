use core::option::OptionTrait;
use starknet::ContractAddress;

// *************************************************************************
//                              TYPES
// *************************************************************************

// * @notice A struct containing campaign data.
// * campaign_address The campaign address of a TGN Campaign
// * campaign_owner The address that created the campaign_address
// * @param metadataURI MetadataURI is used to store the campaigns's metadata, for example:
// displayed name, description, beneficiary, etc.
#[derive(Drop, Serde, starknet::Store)]
pub struct Campaign {
    pub campaign_address: ContractAddress,
    pub campaign_id: u256,
    pub campaign_owner: ContractAddress,
    pub nft_token_uri: ByteArray,
    pub token_id: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct CampaignPool {
    pub campaign_address: ContractAddress,
    pub campaign_pool_id: u256,
    pub campaign_owner: ContractAddress,
    pub nft_token_uri: ByteArray,
    pub token_id: u256,
    pub is_closed: bool,
}

#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub enum CampaignState {
    Active,
    VotingPhase,
    Closed,
    Funded,
    Cancelled
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct CampaignTimeline {
    pub application_deadline: u64,
    pub voting_deadline: u64,
    pub funding_deadline: u64,
    pub created_at: u64,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct CampaignStats {
    pub total_donations: u256,
    pub total_donors: u16,
    pub total_withdrawn: u256,
    pub total_available_withdrawal: u256,
}

