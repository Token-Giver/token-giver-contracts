use starknet::{ClassHash, ContractAddress};
use tokengiver::base::types::{CampaignPool, CampaignState, CampaignTimeline, CampaignStats};
// *************************************************************************
//                              INTERFACE of TOKEN GIVER CAMPAIGN POOL
// *************************************************************************

#[starknet::interface]
pub trait ICampaignPool<TState> {
    fn create_campaign_pool(
        ref self: TState,
        registry_hash: felt252,
        implementation_hash: felt252,
        salt: felt252,
        recipient: ContractAddress,
        campaign_pool_id: u256,
    ) -> ContractAddress;

    fn get_campaign(self: @TState, campaign_address: ContractAddress) -> CampaignPool;

    fn donate_campaign_pool(ref self: TState, campaign_pool_address: ContractAddress, amount: u256);

    fn apply_to_campaign_pool(
        ref self: TState,
        campaign_address: ContractAddress,
        campaign_pool_address: ContractAddress,
        amount: u256,
    );
    fn upgrade(ref self: TState, new_class_hash: ClassHash);

    fn vote_project(
        ref self: TState, campaign_pool_address: ContractAddress, campaign_address: ContractAddress,
    );

    fn get_campaign_application(
        self: @TState, campaign_address: ContractAddress,
    ) -> (ContractAddress, u256);

    fn close_campaign_pool(
        ref self: TState, campaign_pool_address: ContractAddress,
    );

    fn set_campaign_deadlines(
        ref self: TState,
        campaign_address: ContractAddress,
        campaign_timeline: CampaignTimeline,
    );

    fn get_campaign_pool_stats(
        self: @TState, campaign_pool_address: ContractAddress,
    ) -> CampaignStats;

    fn update_campaign_state(
        ref self: TState,
        campaign_address: ContractAddress,
        new_state: CampaignState,
    );
}
