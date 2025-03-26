use starknet::ContractAddress;

#[starknet::contract]
mod CampaignPools {
    // *************************************************************************
    //                            IMPORT
    // *************************************************************************
    use core::traits::TryInto;
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, ClassHash, get_contract_address,
        syscalls::deploy_syscall, SyscallResultTrait, syscalls, class_hash::class_hash_const,
        storage::{Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess}
    };
    use tokengiver::base::errors::Errors;
    use tokengiver::interfaces::ICampaignPool::ICampaignPool;
    use tokengiver::base::types::CampaignPool;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use tokengiver::interfaces::ITokenGiverNft::{
        ITokenGiverNftDispatcher, ITokenGiverNftDispatcherTrait
    };
    use tokengiver::interfaces::IRegistry::{
        IRegistryDispatcher, IRegistryDispatcherTrait, IRegistryLibraryDispatcher
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
            ContractAddress, (ContractAddress, u256)
        >, // map<Campaign Address, (campaign pool address, amount)>
        campaign_pool_count: u16,
        campaign_pool_nft_token: Map<
            ContractAddress, (ContractAddress, u256)
        >, // (recipient, (campaign_address, token_id));
        donations: Map<ContractAddress, u256>,
        donation_count: Map<ContractAddress, u16>,
        donation_details: Map<
            (ContractAddress, ContractAddress), DonationDetails
        >, // map((campaign pool address, Campaign Address), donation_details)
        campaign_votes: Map<(ContractAddress, ContractAddress), u64>,
        // map((campaign_pool_address, campaign_address), num_of_votes)
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
        CreateCampaignPool: CreateCampaignPool,
        DonationMade: DonationMade,
        ApplicationMade: ApplicationMade,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
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
                contract_address: token_giver_nft_contract_address
            };
            let token_id: u256 = nft_contract_dispatcher.mint_token_giver_nft(get_caller_address());

            let campaign_address = IRegistryLibraryDispatcher {
                class_hash: registry_hash.try_into().unwrap()
            }
                .create_account(
                    implementation_hash, token_giver_nft_contract_address, token_id.clone(), salt
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

            self
                .emit(
                    CreateCampaignPool {
                        owner: recipient,
                        campaign_pool_address: campaign_address,
                        token_id,
                        campaign_pool_id: campaign_pool_count.try_into().unwrap(),
                        nft_token_uri: token_uri.clone(),
                        token_giver_nft_address: token_giver_nft_contract_address,
                        block_timestamp: get_block_timestamp()
                    }
                );

            campaign_address
        }

        fn get_campaign(self: @ContractState, campaign_address: ContractAddress) -> CampaignPool {
            self.campaign_pool.read(campaign_address)
        }

        fn donate_campaign_pool(
            ref self: ContractState, campaign_pool_address: ContractAddress, amount: u256
        ) {}

        fn apply_to_campaign_pool(
            ref self: ContractState,
            campaign_address: ContractAddress,
            campaign_pool_address: ContractAddress,
            amount: u256
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
                    }
                );
        }
        fn get_campaign_application(
            self: @ContractState, campaign_address: ContractAddress
        ) -> (ContractAddress, u256) {
            self.campaign_pool_applications.read(campaign_address)
        }

        fn get_votes_count(
            self: @ContractState, campaign_pool_address: ContractAddress,
            campaign_address: ContractAddress
        ) -> u64 {
            self.campaign_votes.read((campaign_pool_address, campaign_address))
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
