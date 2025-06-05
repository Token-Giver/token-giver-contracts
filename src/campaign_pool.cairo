use starknet::ContractAddress;

#[starknet::contract]
mod CampaignPools {
    // *************************************************************************
    //                            IMPORT
    // *************************************************************************
    use core::num::traits::Zero;
    use core::traits::TryInto;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::class_hash::class_hash_const;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
        get_contract_address, syscalls,
    };
    use tokengiver::base::errors::Errors;
    use tokengiver::base::types::{CampaignPool, CampaignState, CampaignTimeline, CampaignStats};
    use tokengiver::interfaces::ICampaignPool::ICampaignPool;
    use tokengiver::interfaces::IRegistry::{
        IRegistryDispatcher, IRegistryDispatcherTrait, IRegistryLibraryDispatcher,
    };
    use tokengiver::interfaces::ITokenGiverNft::{
        ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;


    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    #[storage]
    struct Storage {
        campaign_pool: Map<ContractAddress, CampaignPool>,
        campaign_pool_applications: Map<
            ContractAddress, (ContractAddress, u256),
        >, // map<Campaign Address, (campaign pool address, amount)>
        campaign_pool_count: u16,
        campaign_pool_nft_token: Map<
            ContractAddress, (ContractAddress, u256),
        >, // (recipient, (campaign_address, token_id));
        donations: Map<ContractAddress, u256>,
        donation_count: Map<ContractAddress, u16>,
        donation_details: Map<
            (ContractAddress, ContractAddress), DonationDetails,
        >, // map((campaign pool address, Campaign Address), donation_details)
        strk_address: ContractAddress,
        token_giver_nft_contract_address: ContractAddress,
        token_giver_nft_class_hash: ClassHash,
        token_giver_nft_address: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        donor_votes: Map<(ContractAddress, ContractAddress), VoteData>,
        campaign_votes_count: Map<ContractAddress, u256>,
        campaign_timeline: Map<ContractAddress, CampaignTimeline>,
        campaign_pool_stats: Map<ContractAddress, CampaignStats>,
        campaign_state: Map<ContractAddress, CampaignState>,
    }


    // *************************************************************************
    //                            EVENT
    // *************************************************************************
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CreateCampaignPool: CreateCampaignPool,
        DonationMade: DonationMade,
        ApplicationMade: ApplicationMade,
        DonorVoted: DonorVoted,
        CampaignClosed: CampaignClosed,
        CampaignStateUpdated: CampaignStateUpdated,
        CampaignDeadlineSet: CampaignDeadlineSet,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DonorVoted {
        campaign_address: ContractAddress,
        donor_address: ContractAddress,
        time: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CreateCampaignPool {
        #[key]
        owner: ContractAddress,
        #[key]
        campaign_pool_address: ContractAddress,
        token_id: u256,
        campaign_pool_id: u256,
        nft_token_uri: ByteArray,
        token_giver_nft_address: ContractAddress,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ApplicationMade {
        #[key]
        campaign_pool_address: ContractAddress,
        #[key]
        campaign_address: ContractAddress,
        #[key]
        recipient: ContractAddress,
        amount: u256,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DonationMade {
        #[key]
        campaign_pool_address: ContractAddress,
        #[key]
        donor_address: ContractAddress,
        amount: u256,
        block_timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignClosed {
        #[key]
        campaign_pool_address: ContractAddress,
        block_timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    pub struct CampaignStateUpdated {
        #[key]
        campaign_address: ContractAddress,
        new_state: CampaignState,
        block_timestamp: u64,
    }
    #[derive(Drop, starknet::Event)]
    pub struct CampaignDeadlineSet {
        #[key]
        campaign_address: ContractAddress,
        application_deadline: u64,
        voting_deadline: u64,
        funding_deadline: u64,
        created_at: u64,
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct DonationDetails {
        campaign_address: ContractAddress,
        token_id: u256,
        donor_address: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    pub struct VoteData {
        campaign_address: ContractAddress,
        donor: ContractAddress,
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
        owner: ContractAddress,
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
    impl CampaignPoolImpl of ICampaignPool<ContractState> {
        fn create_campaign_pool(
            ref self: ContractState,
            registry_hash: felt252,
            implementation_hash: felt252,
            salt: felt252,
            recipient: ContractAddress,
            campaign_pool_id: u256,
        ) -> ContractAddress {
            let caller = get_caller_address();
            let campaign_pool_count: u16 = self.campaign_pool_count.read() + 1;
            let token_giver_nft_contract_address = self.token_giver_nft_contract_address.read();
            let nft_contract_dispatcher = ITokenGiverNftDispatcher {
                contract_address: token_giver_nft_contract_address,
            };
            let token_id: u256 = nft_contract_dispatcher.mint_token_giver_nft(get_caller_address());

            let campaign_address = IRegistryLibraryDispatcher {
                class_hash: registry_hash.try_into().unwrap(),
            }
                .create_account(
                    implementation_hash, token_giver_nft_contract_address, token_id.clone(), salt,
                );
            let token_uri = nft_contract_dispatcher.get_token_uri(token_id);
            let campaign_details = CampaignPool {
                campaign_address: campaign_address,
                campaign_pool_id: campaign_pool_count.try_into().unwrap(),
                campaign_owner: recipient,
                nft_token_uri: token_uri.clone(),
                token_id: token_id,
                is_closed: false,
            };

            self.campaign_pool.write(campaign_address, campaign_details);
            self.campaign_pool_nft_token.write(recipient, (campaign_address, token_id));

            self.update_campaign_state(campaign_address, CampaignState::Active,);

            self
                .emit(
                    CreateCampaignPool {
                        owner: recipient,
                        campaign_pool_address: campaign_address,
                        token_id,
                        campaign_pool_id: campaign_pool_count.try_into().unwrap(),
                        nft_token_uri: token_uri.clone(),
                        token_giver_nft_address: token_giver_nft_contract_address,
                        block_timestamp: get_block_timestamp(),
                    },
                );

            campaign_address
        }

        fn vote_project(
            ref self: ContractState,
            campaign_pool_address: ContractAddress,
            campaign_address: ContractAddress,
        ) {
            let caller = get_caller_address();
            assert(
                self.campaign_state.read(campaign_address) == CampaignState::VotingPhase,
                Errors::INVALID_CAMPAIGN
            );

            let user_votes = self.donor_votes.read((caller, campaign_address));
            let caller_donation = self.donations.read(caller);
            let campaign_count = self.campaign_votes_count.read(campaign_address);

            assert(caller_donation > 0, 'Caller not donor');

            assert(user_votes.donor.is_non_zero(), 'Voted already');

            let new_vote = VoteData { campaign_address: campaign_address, donor: caller };

            self.donor_votes.write((caller, campaign_address), new_vote);

            self.campaign_votes_count.write(campaign_address, campaign_count + 1);

            self
                .emit(
                    DonorVoted {
                        campaign_address: campaign_address,
                        donor_address: caller,
                        time: get_block_timestamp(),
                    },
                );
        }

        fn get_campaign(self: @ContractState, campaign_address: ContractAddress) -> CampaignPool {
            self.campaign_pool.read(campaign_address)
        }

        fn donate_campaign_pool(
            ref self: ContractState, campaign_pool_address: ContractAddress, amount: u256,
        ) {}

        fn apply_to_campaign_pool(
            ref self: ContractState,
            campaign_address: ContractAddress,
            campaign_pool_address: ContractAddress,
            amount: u256,
        ) {
            // Get caller address to identify who is applying
            let caller = get_caller_address();

            // Validate that the campaign exists
            // We can do this by attempting to read campaign data and asserting it's valid
            let campaign_exists = self
                .campaign_pool
                .read(campaign_address)
                .campaign_address != starknet::contract_address_const::<0>();
            assert(campaign_exists, Errors::INVALID_CAMPAIGN_ADDRESS);

            // Validate that the campaign pool exists
            let pool_exists = self
                .campaign_pool
                .read(campaign_pool_address)
                .campaign_address != starknet::contract_address_const::<0>();
            assert(pool_exists, Errors::INVALID_POOL_ADDRESS);

            // Ensure amount is valid (not zero)
            assert(amount > 0, Errors::INVALID_AMOUNT);

            // Store the application in the mapping
            self
                .campaign_pool_applications
                .write(campaign_address, (campaign_pool_address, amount));

            // Emit an application event
            self
                .emit(
                    ApplicationMade {
                        campaign_pool_address: campaign_pool_address,
                        campaign_address: campaign_address,
                        recipient: caller,
                        amount: amount,
                        block_timestamp: get_block_timestamp(),
                    },
                );
        }
        fn get_campaign_application(
            self: @ContractState, campaign_address: ContractAddress,
        ) -> (ContractAddress, u256) {
            self.campaign_pool_applications.read(campaign_address)
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }

        fn close_campaign_pool(ref self: ContractState, campaign_pool_address: ContractAddress,) {
            let campaign_pool = self.campaign_pool.read(campaign_pool_address);
            assert(!campaign_pool.is_closed, Errors::CAMPAIGN_POOL_ALREADY_CLOSED);
            assert(
                campaign_pool.campaign_owner == get_caller_address(), Errors::NOT_CAMPAIGN_OWNER,
            );
            assert(
                self.campaign_state.read(campaign_pool.campaign_address) != CampaignState::Closed,
                Errors::CAMPAIGN_POOL_ALREADY_CLOSED
            );

            // Update the campaign pool state to closed
            let mut updated_campaign_pool = campaign_pool;
            updated_campaign_pool.is_closed = true;
            self.campaign_pool.write(campaign_pool_address, updated_campaign_pool);
            self
                .campaign_state
                .write(
                    self.campaign_pool.read(campaign_pool_address).campaign_address,
                    CampaignState::Closed,
                );

            // Emit the CampaignChanged event
            self
                .emit(
                    CampaignStateUpdated {
                        campaign_address: self
                            .campaign_pool
                            .read(campaign_pool_address)
                            .campaign_address,
                        new_state: CampaignState::Closed,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }

        fn set_campaign_deadlines(
            ref self: ContractState,
            campaign_address: ContractAddress,
            campaign_timeline: CampaignTimeline,
        ) {
            // Ensure the caller is the campaign owner
            let campaign_pool = self.campaign_pool.read(campaign_address);
            assert(
                campaign_pool.campaign_owner == get_caller_address(), Errors::NOT_CAMPAIGN_OWNER,
            );

            // Store the campaign timeline
            self.campaign_timeline.write(campaign_address, campaign_timeline);

            // Emit the CampaignDeadlineSet event
            self
                .emit(
                    CampaignDeadlineSet {
                        campaign_address: campaign_address,
                        application_deadline: campaign_timeline.application_deadline,
                        voting_deadline: campaign_timeline.voting_deadline,
                        funding_deadline: campaign_timeline.funding_deadline,
                        created_at: campaign_timeline.created_at,
                    }
                );
        }

        fn get_campaign_pool_stats(
            self: @ContractState, campaign_pool_address: ContractAddress,
        ) -> CampaignStats {
            self.campaign_pool_stats.read(campaign_pool_address)
        }

        fn update_campaign_state(
            ref self: ContractState, campaign_address: ContractAddress, new_state: CampaignState,
        ) {
            // Ensure the caller is the campaign owner
            let campaign_pool = self.campaign_pool.read(campaign_address);
            assert(
                campaign_pool.campaign_owner == get_caller_address(), Errors::NOT_CAMPAIGN_OWNER,
            );

            // Update the campaign state
            self.campaign_state.write(campaign_address, new_state);

            // Emit the CampaignStateUpdated event
            self
                .emit(
                    CampaignStateUpdated {
                        campaign_address: campaign_address,
                        new_state: new_state,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }
    }
}
