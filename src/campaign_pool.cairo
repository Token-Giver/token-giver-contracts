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
    use tokengiver::interfaces::ICampaignPool::ICampaignPool;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;


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
        ) -> ContractAddress {}

        fn donate_campaign_pool(
            ref self: ContractState, campaign_pool_address: ContractAddress, amount: u256
        ) {}

        fn apply_to_campaign_pool(
            ref self: ContractState,
            campaign_address: ContractAddress,
            campaign_pool_address: ContractAddress,
            amount: u256
        ) {}

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
