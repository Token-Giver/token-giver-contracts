use starknet::ContractAddress;

#[starknet::contract]
mod TokengiverCampaign {
    // *************************************************************************
    //                            IMPORT
    // *************************************************************************
    use core::traits::TryInto;
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, ClassHash, get_contract_address,
        syscalls::deploy_syscall, SyscallResultTrait,
        storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess}
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
    use tokengiver::base::errors::Errors::{
        NOT_CAMPAIGN_OWNER, INSUFFICIENT_BALANCE, TRANSFER_FAILED
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct DonationDetails {
        token_id: u256,
        donor_address: ContractAddress,
        amount: u256,
    }

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    #[storage]
    struct Storage {
        campaign: Map<ContractAddress, Campaign>,
        campaigns: Map<u16, ContractAddress>,
        withdrawal_balance: Map<ContractAddress, u256>,
        count: u16,
        donations: Map<ContractAddress, u256>,
        donation_count: Map<ContractAddress, u16>,
        donation_details: Map<ContractAddress, DonationDetails>,
        strk_address: ContractAddress,
        token_giver_nft_address: ContractAddress,
    }

    // *************************************************************************
    //                            EVENT
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CreateCampaign: CreateCampaign,
        DonationMade: DonationMade,
        DeployedTokenGiverNFT: DeployedTokenGiverNFT,
        WithdrawalMade: WithdrawalMade,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreateCampaign {
        #[key]
        owner: ContractAddress,
        #[key]
        campaign_address: ContractAddress,
        token_id: u256,
        token_giver_nft_address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DeployedTokenGiverNFT {
        pub campaign_id: u256,
        pub token_giver_nft_contract_address: ContractAddress,
        pub block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DonationMade {
        #[key]
        campaign_id: u256,
        #[key]
        donor_address: ContractAddress,
        amount: u256,
        token_id: u256,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawalMade {
        #[key]
        campaign_address: ContractAddress,
        #[key]
        recipient: ContractAddress,
        amount: u256,
        block_timestamp: u64,
    }

    // *************************************************************************
    //                              CONSTRUCTOR
    // *************************************************************************
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_giver_nft_address: ContractAddress,
        strk_address: ContractAddress
    ) {
        self.token_giver_nft_address.write(token_giver_nft_address);
        self.strk_address.write(strk_address);
    }

    // *************************************************************************
    //                            EXTERNAL FUNCTIONS
    // *************************************************************************
    #[abi(embed_v0)]
    impl CampaignImpl of ICampaign<ContractState> {
        fn create_campaign(
            ref self: ContractState,
            registry_hash: felt252,
            implementation_hash: felt252,
            salt: felt252,
        ) -> ContractAddress {
            let caller = get_caller_address();
            let nft_address = self.token_giver_nft_address.read();
            let token_giver_nft = ITokenGiverNftDispatcher { contract_address: nft_address };

            /// mint token giver NFT
            let token_id = token_giver_nft.mint_token_giver_nft(caller);

            /// create TBA account
            let count: u16 = self.count.read() + 1;
            let campaign_address = IRegistryLibraryDispatcher {
                class_hash: registry_hash.try_into().unwrap()
            }
                .create_account(implementation_hash, nft_address, token_id, salt);

            /// create campaign
            let new_campaign = Campaign {
                campaign_address, campaign_owner: caller, metadata_URI: "", token_id,
            };

            self.campaign.write(campaign_address, new_campaign);
            self.campaigns.write(count, campaign_address);
            self.count.write(count);
            self
                .emit(
                    CreateCampaign {
                        owner: caller,
                        campaign_address,
                        token_id,
                        token_giver_nft_address: nft_address
                    }
                );

            campaign_address
        }

        /// @notice set campaign metadata_uri (`banner_image, description, campaign_image` to be
        /// uploaded to arweave or ipfs)
        /// @params campaign_address the targeted campaign address
        /// @params metadata_uri the campaign CID
        fn set_campaign_metadata_uri(
            ref self: ContractState, campaign_address: ContractAddress, metadata_uri: ByteArray
        ) {
            let mut campaign: Campaign = self.campaign.read(campaign_address);
            assert(get_caller_address() == campaign.campaign_owner, NOT_CAMPAIGN_OWNER);
            campaign.metadata_URI = metadata_uri;
            self.campaign.write(campaign_address, campaign);
        }

        fn donate(
            ref self: ContractState, campaign_address: ContractAddress, amount: u256, token_id: u256
        ) {
            let donor = get_caller_address();

            let token_address = self.strk_address.read();

            IERC20Dispatcher { contract_address: token_address }
                .approve(get_contract_address(), amount);

            IERC20Dispatcher { contract_address: token_address }
                .transfer_from(donor, campaign_address, amount);

            let prev_count = self.donation_count.read(campaign_address);
            self.donation_count.write(campaign_address, prev_count + 1);

            let prev_donations = self.donations.read(campaign_address);
            self.donations.write(campaign_address, prev_donations + amount);

            let donation_details = DonationDetails { token_id, donor_address: donor, amount, };
            self.donation_details.write(donor, donation_details);

            let prev_withdrawal = self.withdrawal_balance.read(campaign_address);
            self.withdrawal_balance.write(campaign_address, prev_withdrawal + amount);

            self
                .emit(
                    DonationMade {
                        campaign_id: token_id,
                        donor_address: donor,
                        amount: amount,
                        token_id,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }

        fn set_donation_count(ref self: ContractState, campaign_address: ContractAddress) {
            let prev_count: u16 = self.donation_count.read(campaign_address);
            self.donation_count.write(campaign_address, prev_count + 1);
        }

        fn set_donations(ref self: ContractState, campaign_address: ContractAddress, amount: u256) {
            self.donations.write(campaign_address, amount);
        }

        // withdraw function
        fn withdraw(ref self: ContractState, campaign_address: ContractAddress, amount: u256) {
            let campaign: Campaign = self.campaign.read(campaign_address);
            let caller: ContractAddress = get_caller_address();

            assert(caller == campaign.campaign_owner, NOT_CAMPAIGN_OWNER);

            let available_balance: u256 = self.withdrawal_balance.read(campaign_address);
            assert(amount <= available_balance, INSUFFICIENT_BALANCE);

            let token_address = self.strk_address.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let transfer_result = token_dispatcher.transfer_from(campaign_address, caller, amount);
            assert(transfer_result, TRANSFER_FAILED);
            self.withdrawal_balance.write(campaign_address, available_balance - amount);

            self
                .emit(
                    WithdrawalMade {
                        campaign_address,
                        recipient: caller,
                        amount: amount,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }

        fn set_available_withdrawal(
            ref self: ContractState, campaign_address: ContractAddress, amount: u256
        ) {
            self.withdrawal_balance.write(campaign_address, amount);
        }

        // *************************************************************************
        //                            GETTERS
        // *************************************************************************

        fn get_donations(self: @ContractState, campaign_address: ContractAddress) -> u256 {
            self.donations.read(campaign_address)
        }
        fn get_available_withdrawal(
            self: @ContractState, campaign_address: ContractAddress
        ) -> u256 {
            self.withdrawal_balance.read(campaign_address)
        }


        // @notice returns the campaign struct of a campaign address
        // @params campaign_address the targeted campaign address
        fn get_campaign(self: @ContractState, campaign_address: ContractAddress) -> Campaign {
            self.campaign.read(campaign_address)
        }

        fn get_campaign_metadata(
            self: @ContractState, campaign_address: ContractAddress
        ) -> ByteArray {
            let campaign: Campaign = self.campaign.read(campaign_address);
            campaign.metadata_URI
        }


        fn get_campaigns(self: @ContractState) -> Array<ByteArray> {
            let mut campaigns = ArrayTrait::new();
            let count = self.count.read();
            let mut i: u16 = 1;

            while i < count + 1 {
                let campaignAddress: ContractAddress = self.campaigns.read(i);
                let campaign: Campaign = self.campaign.read(campaignAddress);
                campaigns.append(campaign.metadata_URI);
                i += 1;
            };
            campaigns
        }

        fn get_user_campaigns(self: @ContractState, user: ContractAddress) -> Array<ByteArray> {
            let mut campaigns = ArrayTrait::new();
            let count = self.count.read();
            let mut i: u16 = 1;

            while i < count + 1 {
                let campaignAddress: ContractAddress = self.campaigns.read(i);
                let campaign: Campaign = self.campaign.read(campaignAddress);
                if campaign.campaign_owner == user {
                    campaigns.append(campaign.metadata_URI);
                }
                i += 1;
            };
            campaigns
        }

        fn get_donation_count(self: @ContractState, campaign_address: ContractAddress) -> u16 {
            self.donation_count.read(campaign_address)
        }
    }
}
