```cairo
mod helpers {
    use starknet::{ContractAddress, get_caller_address};
    use traits::Into;

    /// Validates that an address is non-zero
    pub fn validate_address(address: ContractAddress, error_msg: felt252) {
        assert(address.0 != 0, error_msg);
    }

    /// Validates that an amount is positive
    pub fn validate_amount(amount: u256, error_msg: felt252) {
        assert(amount > 0, error_msg);
    }

    /// Validates that the current caller has the required role
    pub fn validate_role(expected_role: felt252, caller: ContractAddress) {
        // Check if caller is owner or has management role
        let is_manager = /* role check logic */;
        assert(is_manager, expected_role);
    }

    /// Gets the current block timestamp
    pub fn get_current_timestamp() -> u64 {
        starknet::get_block_timestamp()
    }

    /// Validates campaign pool ID uniqueness
    pub fn validate_unique_pool_id(
        pool_id: u256,
        owner: ContractAddress,
        pools: @Core::collections::HashMap<u256, bool>,
    ) -> bool {
        !pools.contains(&pool_id)
    }

    /// Validates that a hash is non-zero (representing a valid deployed contract)
    pub fn validate_hash(hash: felt252, error_msg: felt252) {
        assert(hash != 0, error_msg);
    }

    /// Calculates maximum campaign pools per user (configurable limit)
    pub const MAX_CAMPAIGN_POOLS_PER_USER: u64 = 10;
}
