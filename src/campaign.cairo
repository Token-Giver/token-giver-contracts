#[starknet::component]
pub mod CampaignComponent {
    // *************************************************************************
    //                            IMPORT
    // *************************************************************************
    use core::traits::TryInto;
    use starknet::{
        ContractAddress, get_caller_address, 
        storage::{
            Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess
        }
    };
    use tokengiver::interfaces::ITokenGiverNft::{
        ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
    };
    use tokengiver::interfaces::IRegistry::{
        IRegistryDispatcher, IRegistryDispatcherTrait, IRegistryLibraryDispatcher
    };
    use tokengiver::interfaces::IERC721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use tokengiver::interfaces::ICampaign::ICampaign;
    use tokengiver::base::types::Campaign;
    use tokengiver::base::errors::Errors::NOT_CAMPAIGN_OWNER;


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    #[storage]
    pub struct Storage {
        campaign: Map<ContractAddress, Campaign>,
        campaigns: Map<u16, ContractAddress>,
        withdrawal_balance: Map<ContractAddress, u256>,
        count: u16,
        donations: Map<ContractAddress, u256>,
        donation_count: Map<ContractAddress, u16>
    }

    // *************************************************************************
    //                            EVENT
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CreateCampaign: CreateCampaign
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreateCampaign {
        #[key]
        owner: ContractAddress,
        #[key]
        campaign_address: ContractAddress,
        token_id: u256,
    }

    // *************************************************************************
    //                            EXTERNAL FUNCTIONS
    // *************************************************************************
    #[embeddable_as(TokenGiverCampaign)]
    impl CampaignImpl<
        TContractState, +HasComponent<TContractState>
    > of ICampaign<ComponentState<TContractState>> {
        fn create_campaign(
            ref self: ComponentState<TContractState>,
            token_giverNft_contract_address: ContractAddress,
            registry_hash: felt252,
            implementation_hash: felt252,
            salt: felt252,
            recipient: ContractAddress
        ) -> ContractAddress {
            let count: u16 = self.count.read() + 1;
            ITokenGiverNftDispatcher { contract_address: token_giverNft_contract_address }
                .mint_token_giver_nft(recipient);
            let token_id = ITokenGiverNftDispatcher {
                contract_address: token_giverNft_contract_address
            }
                .get_user_token_id(recipient);

            let campaign_address = IRegistryLibraryDispatcher {
                class_hash: registry_hash.try_into().unwrap()
            }
                .create_account(
                    implementation_hash, token_giverNft_contract_address, token_id, salt
                );
            let new_campaign = Campaign {
                campaign_address, campaign_owner: recipient, metadata_URI: "",
            };
            self.campaign.entry(campaign_address).write(new_campaign);
            self.campaigns.entry(count).write(campaign_address);
            self.count.write(count);
            self.emit(CreateCampaign { owner: recipient, campaign_address, token_id });
            campaign_address
        }

        /// @notice set campaign metadata_uri (`banner_image, description, campaign_image` to be
        /// uploaded to arweave or ipfs)
        /// @params campaign_address the targeted campaign address
        /// @params metadata_uri the campaign CID
        fn set_campaign_metadata_uri(
            ref self: ComponentState<TContractState>,
            campaign_address: ContractAddress,
            metadata_uri: ByteArray
        ) {
            let mut campaign: Campaign = self.campaign.entry(campaign_address).read();
            assert(get_caller_address() == campaign.campaign_owner, NOT_CAMPAIGN_OWNER);
            campaign.metadata_URI = metadata_uri;
            self.campaign.entry(campaign_address).write(campaign);
        }


        fn set_donation_count(
            ref self: ComponentState<TContractState>, campaign_address: ContractAddress
        ) {
            let prev_count: u16 = self.donation_count.entry(campaign_address).read();
            self.donation_count.entry(campaign_address).write(prev_count + 1);
        }

        fn set_donations(
            ref self: ComponentState<TContractState>,
            campaign_address: ContractAddress,
            amount: u256
        ) {
            self.donations.entry(campaign_address).write(amount);
        }

        fn set_available_withdrawal(
            ref self: ComponentState<TContractState>,
            campaign_address: ContractAddress,
            amount: u256
        ) {
            self.withdrawal_balance.entry(campaign_address).write(amount);
        }

        // *************************************************************************
        //                            GETTERS
        // *************************************************************************

        fn get_donations(
            self: @ComponentState<TContractState>, campaign_address: ContractAddress
        ) -> u256 {
            self.donations.entry(campaign_address).read()
        }
        fn get_available_withdrawal(
            self: @ComponentState<TContractState>, campaign_address: ContractAddress
        ) -> u256 {
            self.withdrawal_balance.entry(campaign_address).read()
        }


        // @notice returns the campaign struct of a campaign address
        // @params campaign_address the targeted campaign address
        fn get_campaign(
            self: @ComponentState<TContractState>, campaign_address: ContractAddress
        ) -> Campaign {
            self.campaign.entry(campaign_address).read()
        }

        fn get_campaign_metadata(
            self: @ComponentState<TContractState>, campaign_address: ContractAddress
        ) -> ByteArray {
            let campaign: Campaign = self.campaign.entry(campaign_address).read();
            campaign.metadata_URI
        }


        fn get_campaigns(self: @ComponentState<TContractState>) -> Array<ByteArray> {
            let mut campaigns = ArrayTrait::new();
            let count = self.count.read();
            let mut i: u16 = 1;

            while i < count
                + 1 {
                    let campaignAddress: ContractAddress = self.campaigns.entry(i).read();
                    let campaign: Campaign = self.campaign.entry(campaignAddress).read();
                    campaigns.append(campaign.metadata_URI);
                    i += 1;
                };
            campaigns
        }

        fn get_user_campaigns(
            self: @ComponentState<TContractState>, user: ContractAddress
        ) -> Array<ByteArray> {
            let mut campaigns = ArrayTrait::new();
            let count = self.count.read();
            let mut i: u16 = 1;

            while i < count
                + 1 {
                    let campaignAddress: ContractAddress = self.campaigns.entry(i).read();
                    let campaign: Campaign = self.campaign.entry(campaignAddress).read();
                    if campaign.campaign_owner == user {
                        campaigns.append(campaign.metadata_URI);
                    }
                    i += 1;
                };
            campaigns
        }

        fn get_donation_count(
            self: @ComponentState<TContractState>, campaign_address: ContractAddress
        ) -> u16 {
            self.donation_count.entry(campaign_address).read()
        }
    }
}
