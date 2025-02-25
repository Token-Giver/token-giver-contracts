use starknet::{
    ContractAddress, get_caller_address, get_block_timestamp, ClassHash, contract_address_const
};
use core::zeroable::Zeroable;
use core::traits::Into;
use tokengiver::base::errors::Errors::{
    INVALID_CAMPAIGN_ADDRESS, INVALID_POOL_ADDRESS, INVALID_AMOUNT
};
use tokengiver::base::types::CampaignPool;
use core::byte_array::ByteArray;
use core::array::ArrayTrait;

#[starknet::contract]
mod CampaignPools {
    use starknet::{
        ContractAddress, get_caller_address, get_block_timestamp, ClassHash, get_contract_address,
        syscalls::deploy_syscall, SyscallResultTrait
    };
    use tokengiver::base::errors::Errors::{
        INVALID_CAMPAIGN_ADDRESS, INVALID_POOL_ADDRESS, INVALID_AMOUNT
    };
    use tokengiver::base::types::CampaignPool;
    use tokengiver::interfaces::ICampaignPool::ICampaignPool;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************
    use core::byte_array::ByteArray;

    #[storage]
    struct Storage {
        campaign_pools: LegacyMap<ContractAddress, CampaignPool>,
        campaign_pool_applications: LegacyMap<(ContractAddress, ContractAddress), u256>,
        campaign_pool_count: u16,
        token_giver_nft_class_hash: ClassHash,
        token_giver_nft_contract_address: ContractAddress,
        strk_address: ContractAddress,
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
        CampaignPoolCreated: CampaignPoolCreated,
        ApplicationMade: ApplicationMade,
        DonationMade: DonationMade,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignPoolCreated {
        #[key]
        campaign_pool_address: ContractAddress,
        #[key]
        recipient: ContractAddress,
        campaign_pool_id: u256,
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
        ) -> ContractAddress {
            // Implementation for creating a campaign pool
            // This is a placeholder - actual implementation would deploy a new pool contract
            let campaign_pool_address = starknet::contract_address_const::<0x123>();

            // Create a new campaign pool record
            let mut data = ArrayTrait::new();
            let new_campaign_pool = CampaignPool {
                campaign_address: starknet::contract_address_const::<0>(),
                campaign_owner: recipient,
                campaign_id: campaign_pool_id,
                nft_token_uri: ByteArray { data: data, pending_word: 0, pending_word_len: 0 },
                token_id: 0,
                is_closed: false,
            };

            self.campaign_pools.write(campaign_pool_address, new_campaign_pool);
            self.campaign_pool_count.write(self.campaign_pool_count.read() + 1);

            self
                .emit(
                    CampaignPoolCreated {
                        campaign_pool_address,
                        recipient,
                        campaign_pool_id,
                        block_timestamp: get_block_timestamp(),
                    }
                );

            campaign_pool_address
        }

        fn donate_campaign_pool(
            ref self: ContractState, campaign_pool_address: ContractAddress, amount: u256
        ) {
            // Implementation for donating to a campaign pool
            // This is a placeholder
            let donor = get_caller_address();

            self
                .emit(
                    DonationMade {
                        campaign_pool_address,
                        donor_address: donor,
                        amount,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }

        fn apply_to_campaign_pool(
            ref self: ContractState,
            campaign_address: ContractAddress,
            campaign_pool_address: ContractAddress,
            amount: u256
        ) {
            // Validate inputs
            // Check that campaign_address is valid (not zero)
            assert(
                campaign_address != starknet::contract_address_const::<0>(),
                INVALID_CAMPAIGN_ADDRESS
            );

            // Check that campaign_pool_address is valid (not zero)
            assert(
                campaign_pool_address != starknet::contract_address_const::<0>(),
                INVALID_POOL_ADDRESS
            );

            // Check that amount is valid (greater than zero)
            assert(amount > 0, INVALID_AMOUNT);

            // Get the caller address (recipient)
            let recipient = get_caller_address();

            // Store the application details in the campaign_pool_applications map
            self
                .campaign_pool_applications
                .write((campaign_address, campaign_pool_address), amount);

            // Emit the ApplicationMade event
            self
                .emit(
                    ApplicationMade {
                        campaign_pool_address,
                        campaign_address,
                        recipient,
                        amount,
                        block_timestamp: get_block_timestamp(),
                    }
                );
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
