#[starknet::contract]
mod TokenGiverCampaign {
    use starknet::{ContractAddress, get_caller_address};
    use tokengiver::campaign::CampaignComponent;

    component!(path: CampaignComponent, storage: campaign, event: CampaignEvent);

    #[abi(embed_v0)]
    impl CampaignImpl = CampaignComponent::TokenGiverCampaign<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        campaign: CampaignComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        CampaignEvent: CampaignComponent::Event
    }
}
