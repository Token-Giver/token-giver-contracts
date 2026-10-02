```cairo
mod errors {
    // Address validation errors
    const ZERO_ADDRESS: felt252 = 'Zero address not allowed';
    const INVALID_RECIPIENT: felt252 = 'Invalid recipient address';

    // Campaign pool errors
    const CAMPAIGN_POOL_CLOSED: felt252 = 'Campaign pool is closed';
    const CAMPAIGN_POOL_NOT_OPEN: felt252 = 'Campaign pool is not open';
    const CAMPAIGN_POOL_ALREADY_EXISTS: felt252 = 'Campaign pool with this ID already exists';
    const MAX_CAMPAIGN_POOLS_REACHED: felt252 = 'Maximum campaign pools per user reached';
    const INVALID_REGISTRY_HASH: felt252 = 'Invalid registry hash';
    const INVALID_IMPLEMENTATION_HASH: felt252 = 'Invalid implementation hash';
    const CAMPAIGN_NOT_IN_POOL: felt252 = 'Campaign does not belong to this pool';

    // Application errors
    const APPLICATION_DEADLINE_PASSED: felt252 = 'Application deadline passed';
    const ALREADY_APPLIED: felt252 = 'Campaign has already applied to this pool';
    const MAX_APPLICATION_AMOUNT_EXCEEDED: felt252 = 'Maximum application amount exceeded';
    const INVALID_APPLICATION_AMOUNT: felt252 = 'Invalid application amount';
    const APPLICATION_NOT_ACCEPTED: felt252 = 'Campaign pool is not accepting applications';

    // Voting errors
    const VOTING_PERIOD_ENDED: felt252 = 'Voting period has ended';
    const VOTING_NOT_ACTIVE: felt252 = 'Voting is not active';
    const INVALID_VOTE_AMOUNT: felt252 = 'Invalid vote amount';
    const CAMPAIGN_NOT_ELIGIBLE: felt252 = 'Campaign is not eligible for voting';

    // Access control errors
    const UNAUTHORIZED: felt252 = 'Unauthorized caller';
    const NOT_CAMPAIN_MANAGER: felt252 = 'Not campaign manager';

    // General errors
    const INVALID_INPUT: felt252 = 'Invalid input parameters';
    const TRANSFER_FAILED: felt252 = 'Token transfer failed';
    const INSUFFICIENT_BALANCE: felt252 = 'Insufficient balance';
}
