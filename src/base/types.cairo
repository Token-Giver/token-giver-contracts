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
    pub campaign_owner: ContractAddress,
    pub metadata_URI: ByteArray,
    pub token_id: u256,
}
