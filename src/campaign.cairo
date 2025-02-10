use starknet::ContractAddress;

#[starknet::contract]
mod TokengiverCampaigns {
    // *************************************************************************
    //                            IMPORT
    // *************************************************************************
    use core::traits::TryInto;
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, ClassHash, get_contract_address,
        syscalls::deploy_syscall, SyscallResultTrait, syscalls, class_hash::class_hash_const,
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
        NOT_CAMPAIGN_OWNER, INSUFFICIENT_BALANCE, TRANSFER_FAILED, NOT_CONTRACT_OWNER
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use token_bound_accounts::interfaces::ILockable::{
        ILockableDispatcher, ILockableDispatcherTrait
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct DonationDetails {
        campaign_address: ContractAddress,
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
        donation_details: Map<
            (ContractAddress, ContractAddress), DonationDetails
        >, // map((), donation_details)
        campaign_nft_token: Map<ContractAddress, (ContractAddress, u256)>,
        strk_address: ContractAddress,
        token_giver_nft_contract_address: ContractAddress,
        token_giver_nft_class_hash: ClassHash,
        token_giver_nft_address: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
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
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreateCampaign {
        #[key]
        owner: ContractAddress,
        #[key]
        campaign_address: ContractAddress,
        token_id: u256,
        nft_token_uri: ByteArray,
        token_giver_nft_address: ContractAddress,
        block_timestamp: u64,
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
        campaign_address: ContractAddress,
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
        token_giver_nft_class_hash: ClassHash,
        token_giver_nft_contract_address: ContractAddress,
        strk_address: ContractAddress,
        owner: ContractAddress
    ) {
        self.token_giver_nft_class_hash.write(token_giver_nft_class_hash);
        self.token_giver_nft_contract_address.write(token_giver_nft_contract_address);
        self.strk_address.write(strk_address);
        self.ownable.initializer(owner);
    }


    // *************************************************************************
    //                            EXTERNAL FUNCTIONS
    // *************************************************************************
    #[abi(embed_v0)]
    impl CampaignImpl of ICampaign<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
        fn create_campaign(
            ref self: ContractState,
            registry_hash: felt252,
            implementation_hash: felt252,
            salt: felt252,
            recipient: ContractAddress
        ) -> ContractAddress {
            let count: u16 = self.count.read() + 1;
            let token_giver_nft_contract_address = self
                .token_giver_nft_contract_address
                .read(); // read nft token giver contract address;

            //set dispatcher
            let token_giver_dispatcher = ITokenGiverNftDispatcher {
                contract_address: token_giver_nft_contract_address
            };

            // mint the nft
            token_giver_dispatcher.mint_token_giver_nft(recipient.clone());

            // get the token base on the user that nft was minted for

            let token_id = token_giver_dispatcher.get_user_token_id(recipient.clone());

            let campaign_address = IRegistryLibraryDispatcher {
                class_hash: registry_hash.try_into().unwrap()
            }
                .create_account(
                    implementation_hash, token_giver_nft_contract_address, token_id.clone(), salt
                );
            let token_uri = token_giver_dispatcher.get_token_uri(token_id);

            let new_campaign = Campaign {
                campaign_address,
                campaign_owner: recipient,
                nft_token_uri: token_uri.clone(),
                token_id: token_id.clone()
            };

            self.campaign.write(campaign_address, new_campaign);
            self.campaigns.write(count, campaign_address);
            self.campaign_nft_token.write(recipient, (campaign_address, token_id));
            self.count.write(count);

            self.withdrawal_balance.write(campaign_address, 0);
            self.donation_count.write(campaign_address, 0);
            self.donations.write(campaign_address, 0);

            self
                .emit(
                    CreateCampaign {
                        owner: recipient,
                        campaign_address,
                        token_id,
                        token_giver_nft_address: token_giver_nft_contract_address,
                        nft_token_uri: token_uri,
                        block_timestamp: get_block_timestamp(),
                    }
                );

            campaign_address
        }

        /// @notice set campaign metadata_uri (`banner_image, description, campaign_image` to be
        /// uploaded to arweave or ipfs)
        /// @params campaign_address the targeted campaign address
        /// @params metadata_uri the campaign CID
        // fn set_campaign_metadata_uri(
        //     ref self: ContractState, campaign_address: ContractAddress, metadata_uri: ByteArray
        // ) {
        //     let mut campaign: Campaign = self.campaign.read(campaign_address);
        //     assert(get_caller_address() == campaign.campaign_owner, NOT_CAMPAIGN_OWNER);
        //     campaign.metadata_URI = metadata_uri;
        //     self.campaign.write(campaign_address, campaign);
        // }

        fn donate(
            ref self: ContractState, campaign_address: ContractAddress, amount: u256, token_id: u256
        ) {
            let donor = get_caller_address();

            // update denotation balance for a compaign
            let prev_donations_balance = self.donations.read(campaign_address);
            self.donations.write(campaign_address, prev_donations_balance + amount);

            // fetch campaign denotion counts and update it
            let prev_count = self.donation_count.read(campaign_address);
            self.donation_count.write(campaign_address, prev_count + 1);

            // save donation details for a compaign
            let donation_details = DonationDetails {
                campaign_address, token_id, donor_address: donor, amount,
            };
            self.donation_details.write((campaign_address, donor), donation_details);

            // fetch withdrawal balance and update it
            let prev_withdrawal = self.withdrawal_balance.read(campaign_address);
            self.withdrawal_balance.write(campaign_address, prev_withdrawal + amount);

            self
                .emit(
                    DonationMade {
                        campaign_address,
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

        fn lock_campaign(
            ref self: ContractState, campaign_address: ContractAddress, lock_until: u64
        ) {
            // Get campaign details
            let campaign: Campaign = self.campaign.read(campaign_address);
            let caller = get_caller_address();

            // Only campaign owner can lock the campaign
            assert(caller == campaign.campaign_owner, NOT_CAMPAIGN_OWNER);

            // Call lock function on the campaign's TBA
            ILockableDispatcher { contract_address: campaign_address }.lock(lock_until);
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

        // fn get_campaign_metadata(
        //     self: @ContractState, campaign_address: ContractAddress
        // ) -> ByteArray {
        //     let campaign: Campaign = self.campaign.read(campaign_address);
        //     campaign.metadata_URI
        // }

        // fn get_campaigns(self: @ContractState) -> Array<ByteArray> {
        //     let mut campaigns = ArrayTrait::new();
        //     let count = self.count.read();
        //     let mut i: u16 = 1;

        //     while i < count + 1 {
        //         let campaignAddress: ContractAddress = self.campaigns.read(i);
        //         let campaign: Campaign = self.campaign.read(campaignAddress);
        //        campaigns.append(campaign.nft_token_uri);
        //         i += 1;
        //     };
        //     campaigns
        // }

        // fn get_user_campaigns(self: @ContractState, user: ContractAddress) -> Array<ByteArray> {
        //     let mut campaigns = ArrayTrait::new();
        //     let count = self.count.read();
        //     let mut i: u16 = 1;

        //     while i < count + 1 {
        //         let campaignAddress: ContractAddress = self.campaigns.read(i);
        //         let campaign: Campaign = self.campaign.read(campaignAddress);
        //         if campaign.campaign_owner == user {
        //             campaigns.append(campaign.nft_token_uri);
        //         }
        //         i += 1;
        //     };
        //     campaigns
        // }

        fn get_donation_count(self: @ContractState, campaign_address: ContractAddress) -> u16 {
            self.donation_count.read(campaign_address)
        }

        fn is_locked(self: @ContractState, campaign_address: ContractAddress) -> (bool, u64) {
            ILockableDispatcher { contract_address: campaign_address }.is_locked()
        }

        fn update_token_giver_nft(
            ref self: ContractState,
            token_giver_nft_class_hash: ClassHash,
            token_giver_nft_contract_address: ContractAddress
        ) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();
            self.token_giver_nft_class_hash.write(token_giver_nft_class_hash);
            self.token_giver_nft_contract_address.write(token_giver_nft_contract_address);
        }
    }
}
