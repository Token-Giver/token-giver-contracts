use starknet::ContractAddress;
use tokengiver::base::types::Campaign;
// *************************************************************************
//                              INTERFACE of TOKEN GIVER NFT
// *************************************************************************

#[starknet::interface]
pub trait ICampaign<TState> {
    fn create_campaign(
        ref self: TState, registry_hash: felt252, implementation_hash: felt252, salt: felt252,
    ) -> ContractAddress;
    fn set_campaign_metadata_uri(
        ref self: TState, campaign_address: ContractAddress, metadata_uri: ByteArray
    );
    fn set_donation_count(ref self: TState, campaign_address: ContractAddress);
    fn set_available_withdrawal(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn set_donations(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn donate(ref self: TState, campaign_address: ContractAddress, amount: u256, token_id: u256);
    fn withdraw(ref self: TState, campaign_address: ContractAddress, amount: u256);


    // Getters
    fn get_campaign_metadata(self: @TState, campaign_address: ContractAddress) -> ByteArray;
    fn get_campaign(self: @TState, campaign_address: ContractAddress) -> Campaign;
    fn get_campaigns(self: @TState) -> Array<ByteArray>;
    fn get_user_campaigns(self: @TState, user: ContractAddress) -> Array<ByteArray>;
    fn get_donation_count(self: @TState, campaign_address: ContractAddress) -> u16;
    fn get_available_withdrawal(self: @TState, campaign_address: ContractAddress) -> u256;
    fn get_donations(self: @TState, campaign_address: ContractAddress) -> u256;
}
