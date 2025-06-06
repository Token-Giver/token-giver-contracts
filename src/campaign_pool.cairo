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
    use tokengiver::base::types::CampaignPool;
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
       // To track existing campaign pool IDs
        campaign_pool_id_exists: Map<u256, bool>, 
       // To track campaign pools per user 
        user_campaign_pool_count: Map<ContractAddress, u16>, 
        max_pools_per_user: u16,
        // New storage for campaign-pool relationships
        campaign_to_pool: Map<ContractAddress, ContractAddress>, // Maps campaign address to its pool
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        donor_votes: Map<(ContractAddress, ContractAddress), VoteData>, 
        campaign_votes_count: Map<ContractAddress, u256>,
        // New storage for tracking applications
        campaign_applied_to_pool: Map<(ContractAddress, ContractAddress), bool>, // Maps (campaign, pool) to application status
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
        max_pools_per_user: u16,
    ) {
        self.token_giver_nft_class_hash.write(token_giver_nft_class_hash);
        self.token_giver_nft_contract_address.write(token_giver_nft_contract_address);
        self.strk_address.write(strk_address);
        self.ownable.initializer(owner);
        self.max_pools_per_user.write(max_pools_per_user);
    }

    // *************************************************************************
    //                            VALIDATION HELPERS
    // *************************************************************************
    #[generate_trait]
    impl ValidationImpl of ValidationTrait {
        fn validate_address(address: ContractAddress) {
            assert(!address.is_zero(), Errors::ZERO_ADDRESS);
        }
        
        fn validate_hash(hash: felt252) {
            assert(hash != 0, Errors::INVALID_REGISTRY_HASH);
        }
        fn validate_pool_exists(self: @ContractState, pool_id: u256) {
            let existing_pool = self.campaign_pool_id_exists.read(pool_id);
            assert(existing_pool == true, Errors::CAMPAIGN_POOL_EXISTS);
        }

        fn max_pools_per_user(self: @ContractState, user: ContractAddress) {
            let user_pools = self.user_campaign_pool_count.read(user);
            let max_pools = self.max_pools_per_user.read();
            assert(user_pools < max_pools, Errors::MAX_POOLS_EXCEEDED);
        }

        fn validate_pool_active(self: @ContractState, pool_address: ContractAddress) {
            let pool = self.campaign_pool.read(pool_address);
            assert(!pool.is_closed, Errors::CAMPAIGN_POOL_CLOSED);
        }

        fn validate_campaign_in_pool(
            self: @ContractState, 
            campaign_address: ContractAddress, 
            pool_address: ContractAddress
        ) {
            let campaign_pool = self.campaign_to_pool.read(campaign_address);
            assert(campaign_pool == pool_address, Errors::CAMPAIGN_NOT_IN_POOL);
        }

    
        fn validate_voting_period(self: @ContractState, pool_address: ContractAddress) {
            let pool = self.campaign_pool.read(pool_address);
            let current_time = get_block_timestamp();
            
            // Check if voting has started
            assert(current_time >= pool.voting_start_time, Errors::VOTING_NOT_STARTED);
            // Check if voting has ended
            assert(current_time <= pool.voting_end_time, Errors::VOTING_PERIOD_ENDED);
        }

       
        fn validate_can_apply(
            self: @ContractState,
            campaign_address: ContractAddress,
            campaign_pool_address: ContractAddress,
            amount: u256,
        ) {
            let pool = self.campaign_pool.read(campaign_pool_address);
            let current_time = get_block_timestamp();
            
            // Check if pool accepts applications
            assert(pool.accepts_applications, Errors::APPLICATIONS_NOT_ACCEPTED);
            
            // Check application deadline
            assert(current_time <= pool.application_deadline, Errors::APPLICATION_DEADLINE_PASSED);
            
            // Check if campaign has already applied
            let has_applied = self.campaign_applied_to_pool.read((campaign_address, campaign_pool_address));
            assert(!has_applied, Errors::ALREADY_APPLIED);
            
            // Validate application amount
            assert(amount <= pool.max_application_amount, Errors::AMOUNT_EXCEEDS_MAX);
        }
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
            voting_duration: u64, // Duration in seconds for the voting period
            application_duration: u64, // Duration in seconds for the application period
            max_application_amount: u256, // Maximum amount that can be requested in applications
        ) -> ContractAddress {
            let caller = get_caller_address();

            // --- Input Validations ---
            ValidationImpl::validate_address(recipient);
            ValidationImpl::validate_hash(registry_hash);
            ValidationImpl::validate_hash(implementation_hash);
            ValidationImpl::validate_pool_exists(@self, campaign_pool_id);
            ValidationImpl::max_pools_per_user(@self, caller);

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
            let current_time = get_block_timestamp();
            let campaign_details = CampaignPool {
                campaign_address: campaign_address,
                campaign_pool_id: campaign_pool_count.try_into().unwrap(),
                campaign_owner: recipient,
                nft_token_uri: token_uri.clone(),
                token_id: token_id,
                is_closed: false,
                voting_start_time: current_time + application_duration, // Voting starts after application period
                voting_end_time: current_time + application_duration + voting_duration, // Total duration
                accepts_applications: true,
                application_deadline: current_time + application_duration,
                max_application_amount: max_application_amount,
            };

            self.campaign_pool.write(campaign_address, campaign_details);
            self.campaign_pool_nft_token.write(recipient, (campaign_address, token_id));
            // Record campaign-pool relationship - Map campaign address to its pool address
            self.campaign_to_pool.write(campaign_address, campaign_address); 
            let user_pools = self.user_campaign_pool_count.read(caller);
            self.user_campaign_pool_count.write(recipient, user_pools + 1);
            self.campaign_pool_id_exists.write(campaign_pool_id, true);
        

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

             // Validate pool is active
             ValidationImpl::validate_pool_active(@self, campaign_pool_address);
            // Validate campaign belongs to the specified pool
            ValidationImpl::validate_campaign_in_pool(@self, campaign_address, campaign_pool_address);
           // Validate voting period
            ValidationImpl::validate_voting_period(@self, campaign_pool_address);

            
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
            let campaign_exists = self
                .campaign_pool
                .read(campaign_address)
                .campaign_address != starknet::contract_address_const::<0>();
            assert(campaign_exists, Errors::INVALID_CAMPAIGN_ADDRESS);

            // Validate that the campaign pool exists and is valid for applications
            let pool_exists = self
                .campaign_pool
                .read(campaign_pool_address)
                .campaign_address != starknet::contract_address_const::<0>();
            assert(pool_exists, Errors::INVALID_POOL_ADDRESS);

            // Validate application requirements
            ValidationImpl::validate_can_apply(@self, campaign_address, campaign_pool_address, amount);

            // Store the application
            self.campaign_pool_applications.write(campaign_address, (campaign_pool_address, amount));
            // Mark campaign as having applied to this pool
            self.campaign_applied_to_pool.write((campaign_address, campaign_pool_address), true);
            self.campaign_to_pool.write(campaign_address, campaign_pool_address);

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
    }
}
