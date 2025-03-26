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

