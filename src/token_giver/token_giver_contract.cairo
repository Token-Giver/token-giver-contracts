```cairo
use openzeppelin::access::ownable::OwnableComponent;
use openzeppelin::token::erc20::ERC20Component;
use openzeppelin::token::erc20::IERC20interface;
use starknet::ContractAddress;
use core::traits::Into;
use token_giver::errors::{ZERO_ADDRESS, CAMPAIGN_POOL_CLOSED, APPLICATION_DEADLINE_PASSED, 
                          CAMPAIGN_POOL_ALREADY_EXISTS, MAX_CAMPAIGN_POOLS_REACHED,
                          INVALID_REGISTRY_HASH, INVALID_IMPLEMENTATION_HASH,
                          CAMPAIGN_NOT_IN_POOL, ALREADY_APPLIED, MAX_APPLICATION_AMOUNT_EXCEEDED,
                          INVALID_APPLICATION_AMOUNT, APPLICATION_NOT_ACCEPTED,
                          VOTING_PERIOD_ENDED, VOTING_NOT_ACTIVE, INVALID_VOTE_AMOUNT,
                          CAMPAIGN_NOT_ELIGIBLE, UNAUTHORIZED, NOT_CAMPAIN_MANAGER};
use token_giver::helpers::{validate_address, validate_amount, validate_hash,
                           validate_unique_pool_id, get_current_timestamp,
                           MAX_CAMPAIGN_POOLS_PER_USER};

#[starknet::interface]
trait ITokenGiverTrait<TContractState> {
    fn create_campaign_pool(
        ref self: TContractState,
        registry_hash: felt252,
        implementation_hash: felt252,
        salt: felt252,
        recipient: ContractAddress,
        campaign_pool_id: u256,
    ) -> ContractAddress;

    fn vote_project(
        ref self: TContractState,
        campaign_pool_id: u256,
        campaign_id: u256,
        amount: u256,
    );

    fn apply_to_campaign_pool(
        ref self: TContractState,
        campaign_pool_id: u256,
        campaign_id: u256,
        application_amount: u256,
    );

    fn get_campaign_pool_status(campaign_pool_id: u256) -> felt252;
}

#[starknet::contract]
mod TokenGiver {
    use super::ITokenGiverTrait;
    use openzeppelin::access::ownable::OwnableStorage;
    use openzeppelin::token::erc20::ERC20;
    use starknet::ContractAddress;
    use core::traits::Into;
    use core::integer_trait::Integer;
    use token_giver::errors::*;
    use token_giver::helpers::*;

    #[storage]
    struct Storage {
        ownable: OwnableStorage,
        /// Mapping from campaign pool ID to pool data
        campaign_pools: Core::collections::HashMap<u256, CampaignPool>,
        /// Mapping from campaign ID to campaigns in pools
        campaigns: Core::collections::HashMap<u256, Campaign>,
        /// Mapping from owner to their campaign pool count
        owner_pool_count: Core::collections::HashMap<ContractAddress, u64>,
        /// Mapping from owner to their pool IDs (for uniqueness checks)
        owner_pool_ids: Core::collections::HashMap<ContractAddress, Core::collections::HashMap<u256, bool>>,
        /// Voting token contract
        voting_token: Option<ContractAddress>,
        /// Maximum application amount per campaign
        max_application_amount: u256,
    }

    #[derive(Copy, Drop, serdect::ser::Serialize, serdect::ser::Deserialize)]
    struct CampaignPool {
        id: u256,
        registry_hash: felt252,
        implementation_hash: felt252,
        creator: ContractAddress,
        recipient: ContractAddress,
        status: PoolStatus,
        created_at: u64,
        application_deadline: u64,
        voting_deadline: u64,
        total_applied: u256,
    }

    #[derive(Copy, Drop, Clone, Eq, serdect::ser::Serialize, serdect::ser::Deserialize)]
    enum PoolStatus {
        Open,
        Closed,
        Active,
        Finished,
    }

    #[derive(Copy, Drop, Clone)]
    struct Campaign {
        id: u256,
        pool_id: u256,
        applicant: ContractAddress,
        application_amount: u256,
        applied_at: u64,
        votes_received: u256,
        status: CampaignStatus,
    }

    #[derive(Copy, Drop, Clone, Eq)]
    enum CampaignStatus {
        Pending,
        Approved,
        Rejected,
        Funded,
    }

    #[abi(embed_v0)]
    impl OwnableImpl of openzeppelin::access::ownable::OwnableInterface {
        fn owner(self: @T) -> ContractAddress {
            self.ownerable.read().owner.get()
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_owner: ContractAddress,
        _voting_token: Option<ContractAddress>,
        _max_application_amount: u256,
    ) {
        self.ownerable.initializer(initial_owner);
        self.voting_token.write(_voting_token);
        self.max_application_amount.write(_max_application_amount);
    }

    fn create_campaign_pool(
        ref self: ContractState,
        registry_hash: felt252,
        implementation_hash: felt252,
        salt: felt252,
        recipient: ContractAddress,
        campaign_pool_id: u256,
    ) -> ContractAddress {
        let caller = starknet::get_caller_address();

        // Validate recipient is not zero address
        validate_address(recipient, ZERO_ADDRESS);

        // Validate hashes are not zero
        validate_hash(registry_hash, INVALID_REGISTRY_HASH);
        validate_hash(implementation_hash, INVALID_IMPLEMENTATION_HASH);

        // Validate campaign pool ID uniqueness
        let mut pool_ids = self.owner_pool_ids.read().get(caller).unwrap_or_default();
        assert(
            validate_unique_pool_id(campaign_pool_id, caller, @pool_ids),
            CAMPAIGN_POOL_ALREADY_EXISTS
        );

        // Check maximum campaign pools per user
        let pool_count = self.owner_pool_count.read().get(caller).unwrap_or(0);
        assert(pool_count < MAX_CAMPAIGN_POOLS_PER_USER, MAX_CAMPAIGN_POOLS_REACHED);

        let current_timestamp = get_current_timestamp();

        let pool = CampaignPool {
            id: campaign_pool_id,
            registry_hash,
            implementation_hash,
            creator: caller,
            recipient,
            status: PoolStatus::Open,
            created_at: current_timestamp,
            application_deadline: current_timestamp + 30 days_in_seconds(),
            voting_deadline: current_timestamp + 60 days_in_seconds(),
            total_applied: 0,
        };

        // Update storage
        self.campaign_pools.write().insert(campaign_pool_id, pool);
        pool_ids.insert(campaign_pool_id, true);
        self.owner_pool_ids.write().insert(caller, pool_ids);
        self.owner_pool_count.write().insert(caller, pool_count + 1);

        // Deploy the campaign pool contract
        let pool_contract = starknet::class_hash::deploy(implementation_hash, salt);

        pool_contract
    }

    fn vote_project(
        ref self: ContractState,
        campaign_pool_id: u256,
        campaign_id: u256,
        amount: u256,
    ) {
        // Validate vote amount
        validate_amount(amount, INVALID_VOTE_AMOUNT);

        // Get and validate campaign pool
        let pool = self.campaign_pools.read().get(campaign_pool_id)
            .unwrap_relocatable() as &CampaignPool;

        // Check pool is still active/open for voting
        assert(pool.status == PoolStatus::Active, CAMPAIGN_POOL_CLOSED);

        // Validate voting period hasn't ended
        let current_time = get_current_timestamp();
        assert(current_time <= pool.voting_deadline, VOTING_PERIOD_ENDED);

        // Get and validate campaign belongs to this pool
        let campaign = self.campaigns.read().get(campaign_id)
            .unwrap_relocatable() as &Campaign;
        assert(campaign.pool_id == campaign_pool_id, CAMPAIGN_NOT_IN_POOL);
        assert(campaign.status == CampaignStatus::Approved, CAMPAIGN_NOT_ELIGIBLE);

        // Process the vote
        let mut updated_campaign = *campaign;
        updated_campaign.votes_received += amount;
        self.campaigns.write().insert(campaign_id, updated_campaign);

        // Transfer voting tokens
        let token_address = self.voting_token.read().unwrap();
        assert(token_address.is_some(), VOTING_NOT_ACTIVE);
        let token = IERC20interface::MulticallProxy { contract_address: token_address.unwrap() };
        token.transfer_from(starknet::get_caller_address(), pool.recipient, amount);
    }

    fn apply_to_campaign_pool(
        ref self: ContractState,
        campaign_pool_id: u256,
        campaign_id: u256,
        application_amount: u256,
    ) {
        let caller = starknet::get_caller_address();

        // Validate application amount
        validate_amount(application_amount, INVALID_APPLICATION_AMOUNT);

        // Validate against max application amount
        let max_amount = self.max_application_amount.read();
        assert(application_amount <= max_amount, MAX_APPLICATION_AMOUNT_EXCEEDED);

        // Get and validate campaign pool
        let pool = self.campaign_pools.read().get(campaign_pool_id)
            .unwrap_relocatable() as &CampaignPool;

        // Check pool accepts applications
        assert(pool.status == PoolStatus::Open, APPLICATION_NOT_ACCEPTED);

        // Validate application deadline
        let current_time = get_current_timestamp();
        assert(current_time <= pool.application_deadline, APPLICATION_DEADLINE_PASSED);

        // Check campaign hasn't already applied
        if self.campaigns.read().contains(&campaign_id) {
            let existing_campaign = self.campaigns.read().get(campaign_id).unwrap_relocatable();
            assert((*existing_campaign as &Campaign).pool_id != campaign_pool_id, ALREADY_APPLIED);
        }

        // Create the campaign application
        let campaign = Campaign {
            id: campaign_id,
            pool_id: campaign_pool_id,
            applicant: caller,
            application_amount,
            applied_at: current_time,
            votes_received: 0,
            status: CampaignStatus::Pending,
        };

        // Update pool total applied
        let mut updated_pool = *pool;
        updated_pool.total_applied += application_amount;
        self.campaign_pools.write().insert(campaign_pool_id, updated_pool);

        self.campaigns.write().insert(campaign_id, campaign);
    }

    fn get_campaign_pool_status(campaign_pool_id: u256) -> felt252 {
        let pool = self.campaign_pools.read().get(campaign_pool_id).unwrap_relocatable();
        *pool as &PoolStatus
    }
}
