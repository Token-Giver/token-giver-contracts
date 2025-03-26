use starknet::{ContractAddress, ClassHash};
use tokengiver::base::types::Campaign;
// *************************************************************************
//                              INTERFACE of TOKEN GIVER NFT
// *************************************************************************

#[starknet::interface]
pub trait ICampaign<TState> {
    fn create_campaign(
        ref self: TState,
        registry_hash: felt252,
        implementation_hash: felt252,
        salt: felt252,
        recipient: ContractAddress,
        campaign_id: u256,
    ) -> ContractAddress;
    // fn set_campaign_metadata_uri(
    //     ref self: TState, campaign_address: ContractAddress, metadata_uri: ByteArray
    // );
    fn set_donation_count(ref self: TState, campaign_address: ContractAddress);
    fn set_available_withdrawal(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn set_donations(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn donate(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn withdraw(ref self: TState, campaign_address: ContractAddress, amount: u256);
    fn vote_project(
        ref self: TState, campaign_pool_address: ContractAddress, campaign_address: ContractAddress

    fn upgrade(ref self: TState, new_class_hash: ClassHash);
    fn lock_campaign(ref self: TState, campaign_address: ContractAddress, lock_until: u64);
    fn update_token_giver_nft(
        ref self: TState,
        token_giver_nft_class_hash: ClassHash,
        token_giver_nft_contract_address: ContractAddress
    );

    //     fn approve_campaign_spending(ref self: TState, campaign_address: ContractAddress);

    // Getters
    //  fn get_campaign_metadata(self: @TState, campaign_address: ContractAddress) -> ByteArray;
    fn get_campaign(self: @TState, campaign_address: ContractAddress) -> Campaign;
    // fn get_campaigns(self: @TState) -> Array<ByteArray>;
    //  fn get_user_campaigns(self: @TState, user: ContractAddress) -> Array<ByteArray>;
    fn get_donation_count(self: @TState, campaign_address: ContractAddress) -> u16;
    fn get_available_withdrawal(self: @TState, campaign_address: ContractAddress) -> u256;
    fn get_donations(self: @TState, campaign_address: ContractAddress) -> u256;
    fn is_locked(self: @TState, campaign_address: ContractAddress) -> (bool, u64);
}
