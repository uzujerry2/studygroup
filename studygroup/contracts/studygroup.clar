;; Study Group - Decentralized Learning Platform with Commitment Stakes
;; Form study groups, stake tokens for commitment, complete milestones, earn rewards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-group-full (err u105))
(define-constant err-already-member (err u106))
(define-constant err-group-closed (err u107))
(define-constant err-contract-paused (err u108))
(define-constant err-milestone-incomplete (err u109))

;; Data Variables
(define-data-var next-group-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var min-stake-amount uint u5000000) ;; 5 STX minimum
(define-data-var platform-reward-pool uint u0)
(define-data-var contract-paused bool false)
(define-data-var completion-bonus-rate uint u1000) ;; 10% bonus on stake return

;; Data Maps
(define-map study-groups
    { group-id: uint }
    {
        organizer: principal,
        group-name: (string-ascii 64),
        subject: (string-ascii 32),
        description: (string-ascii 256),
        max-members: uint,
        current-members: uint,
        stake-per-member: uint,
        total-staked: uint,
        duration-blocks: uint,
        start-block: uint,
        end-block: uint,
        milestone-count: uint,
        completed-milestones: uint,
        status: (string-ascii 16),
        success-threshold: uint,
        created-at: uint
    }
)

(define-map group-members
    { group-id: uint, member: principal }
    {
        stake-amount: uint,
        joined-at: uint,
        is-active: bool,
        milestones-completed: uint,
        contribution-score: uint
    }
)

(define-map learning-milestones
    { milestone-id: uint }
    {
        group-id: uint,
        title: (string-ascii 64),
        description: (string-ascii 256),
        required-completions: uint,
        current-completions: uint,
        reward-pool: uint,
        deadline: uint,
        is-completed: bool,
        created-at: uint
    }
)

(define-map milestone-completions
    { milestone-id: uint, member: principal }
    {
        proof-hash: (string-ascii 64),
        completion-date: uint,
        peer-verifications: uint,
        is-verified: bool
    }
)

(define-map peer-verifications
    { milestone-id: uint, member: principal, verifier: principal }
    {
        is-approved: bool,
        feedback: (string-ascii 128),
        verification-date: uint
    }
)

(define-map learner-profiles
    { learner: principal }
    {
        username: (string-ascii 32),
        groups-joined: uint,
        groups-completed: uint,
        milestones-achieved: uint,
        total-staked: uint,
        total-earned: uint,
        reputation-score: uint,
        success-rate: uint
    }
)

(define-map subject-stats
    { subject: (string-ascii 32) }
    {
        total-groups: uint,
        completed-groups: uint,
        total-learners: uint,
        success-rate: uint
    }
)

;; Authorization Functions
(define-private (is-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (is-group-organizer (group-id uint))
    (match (map-get? study-groups { group-id: group-id })
        group (is-eq tx-sender (get organizer group))
        false
    )
)

(define-private (is-group-member (group-id uint) (member principal))
    (match (map-get? group-members { group-id: group-id, member: member })
        member-data (get is-active member-data)
        false
    )
)

;; Admin Functions
(define-public (set-min-stake (new-min uint))
    (begin
        (asserts! (is-owner) err-owner-only)
        (var-set min-stake-amount new-min)
        (ok true)
    )
)

(define-public (add-to-reward-pool (amount uint))
    (begin
        (asserts! (is-owner) err-owner-only)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set platform-reward-pool (+ (var-get platform-reward-pool) amount))
        (ok true)
    )
)

(define-public (pause-contract)
    (begin
        (asserts! (is-owner) err-owner-only)
        (var-set contract-paused true)
        (ok true)
    )
)

(define-public (unpause-contract)
    (begin
        (asserts! (is-owner) err-owner-only)
        (var-set contract-paused false)
        (ok true)
    )
)

;; Profile Functions
(define-public (create-learner-profile (username (string-ascii 32)))
    (let
        ((existing-profile (map-get? learner-profiles { learner: tx-sender })))
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-none existing-profile) err-already-member)
            (asserts! (> (len username) u0) err-invalid-input)
            
            (map-set learner-profiles
                { learner: tx-sender }
                {
                    username: username,
                    groups-joined: u0,
                    groups-completed: u0,
                    milestones-achieved: u0,
                    total-staked: u0,
                    total-earned: u0,
                    reputation-score: u100,
                    success-rate: u0
                }
            )
            (ok true)
        )
    )
)

;; Study Group Creation and Management
(define-public (create-study-group
    (group-name (string-ascii 64))
    (subject (string-ascii 32))
    (description (string-ascii 256))
    (max-members uint)
    (stake-per-member uint)
    (duration-blocks uint)
    (success-threshold uint))
    (let
        (
            (group-id (var-get next-group-id))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (> (len group-name) u0) err-invalid-input)
            (asserts! (and (>= max-members u2) (<= max-members u20)) err-invalid-input)
            (asserts! (>= stake-per-member (var-get min-stake-amount)) err-insufficient-funds)
            (asserts! (> duration-blocks u0) err-invalid-input)
            (asserts! (and (> success-threshold u0) (<= success-threshold u100)) err-invalid-input)
            
            ;; Organizer stakes first
            (try! (stx-transfer? stake-per-member tx-sender (as-contract tx-sender)))
            
            ;; Create group
            (map-set study-groups
                { group-id: group-id }
                {
                    organizer: tx-sender,
                    group-name: group-name,
                    subject: subject,
                    description: description,
                    max-members: max-members,
                    current-members: u1,
                    stake-per-member: stake-per-member,
                    total-staked: stake-per-member,
                    duration-blocks: duration-blocks,
                    start-block: u0,
                    end-block: (+ u0 duration-blocks),
                    milestone-count: u0,
                    completed-milestones: u0,
                    status: "forming",
                    success-threshold: success-threshold,
                    created-at: u0
                }
            )
            
            ;; Add organizer as first member
            (map-set group-members
                { group-id: group-id, member: tx-sender }
                {
                    stake-amount: stake-per-member,
                    joined-at: u0,
                    is-active: true,
                    milestones-completed: u0,
                    contribution-score: u0
                }
            )
            
            ;; Update user stats
            (update-learner-stats tx-sender stake-per-member true)
            
            ;; Update subject stats
            (update-subject-stats subject true false)
            
            ;; Increment group ID
            (var-set next-group-id (+ group-id u1))
            
            (ok group-id)
        )
    )
)

(define-public (join-study-group (group-id uint))
    (let
        (
            (group-data (unwrap! (map-get? study-groups { group-id: group-id }) err-not-found))
            (stake-amount (get stake-per-member group-data))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-eq (get status group-data) "forming") err-group-closed)
            (asserts! (< (get current-members group-data) (get max-members group-data)) err-group-full)
            (asserts! (not (is-group-member group-id tx-sender)) err-already-member)
            
            ;; Stake tokens
            (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
            
            ;; Add member
            (map-set group-members
                { group-id: group-id, member: tx-sender }
                {
                    stake-amount: stake-amount,
                    joined-at: u0,
                    is-active: true,
                    milestones-completed: u0,
                    contribution-score: u0
                }
            )
            
            ;; Update group
            (let
                ((new-member-count (+ (get current-members group-data) u1)))
                (begin
                    (map-set study-groups
                        { group-id: group-id }
                        (merge group-data {
                            current-members: new-member-count,
                            total-staked: (+ (get total-staked group-data) stake-amount),
                            status: (if (is-eq new-member-count (get max-members group-data))
                                "active"
                                "forming"
                            )
                        })
                    )
                    
                    ;; Update user stats
                    (update-learner-stats tx-sender stake-amount true)
                    
                    (ok true)
                )
            )
        )
    )
)

(define-public (create-milestone
    (group-id uint)
    (title (string-ascii 64))
    (description (string-ascii 256))
    (required-completions uint)
    (reward-pool uint)
    (deadline uint))
    (let
        (
            (milestone-id (var-get next-milestone-id))
            (group-data (unwrap! (map-get? study-groups { group-id: group-id }) err-not-found))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-group-organizer group-id) err-unauthorized)
            (asserts! (or (is-eq (get status group-data) "forming") (is-eq (get status group-data) "active")) err-group-closed)
            (asserts! (> (len title) u0) err-invalid-input)
            (asserts! (and (> required-completions u0) (<= required-completions (get current-members group-data))) err-invalid-input)
            (asserts! (> deadline u0) err-invalid-input)
            
            (map-set learning-milestones
                { milestone-id: milestone-id }
                {
                    group-id: group-id,
                    title: title,
                    description: description,
                    required-completions: required-completions,
                    current-completions: u0,
                    reward-pool: reward-pool,
                    deadline: deadline,
                    is-completed: false,
                    created-at: u0
                }
            )
            
            ;; Update group milestone count
            (map-set study-groups
                { group-id: group-id }
                (merge group-data {
                    milestone-count: (+ (get milestone-count group-data) u1)
                })
            )
            
            ;; Increment milestone ID
            (var-set next-milestone-id (+ milestone-id u1))
            
            (ok milestone-id)
        )
    )
)

(define-public (submit-milestone-completion
    (milestone-id uint)
    (proof-hash (string-ascii 64)))
    (let
        (
            (milestone-data (unwrap! (map-get? learning-milestones { milestone-id: milestone-id }) err-not-found))
            (existing-completion (map-get? milestone-completions { milestone-id: milestone-id, member: tx-sender }))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-group-member (get group-id milestone-data) tx-sender) err-unauthorized)
            (asserts! (is-none existing-completion) err-already-member)
            (asserts! (not (get is-completed milestone-data)) err-group-closed)
            (asserts! (> (len proof-hash) u0) err-invalid-input)
            
            (map-set milestone-completions
                { milestone-id: milestone-id, member: tx-sender }
                {
                    proof-hash: proof-hash,
                    completion-date: u0,
                    peer-verifications: u0,
                    is-verified: false
                }
            )
            
            (ok true)
        )
    )
)

(define-public (verify-peer-completion
    (milestone-id uint)
    (member principal)
    (is-approved bool)
    (feedback (string-ascii 128)))
    (let
        (
            (milestone-data (unwrap! (map-get? learning-milestones { milestone-id: milestone-id }) err-not-found))
            (completion-data (unwrap! (map-get? milestone-completions { milestone-id: milestone-id, member: member }) err-not-found))
            (existing-verification (map-get? peer-verifications { milestone-id: milestone-id, member: member, verifier: tx-sender }))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-group-member (get group-id milestone-data) tx-sender) err-unauthorized)
            (asserts! (not (is-eq tx-sender member)) err-unauthorized)
            (asserts! (is-none existing-verification) err-already-member)
            
            ;; Record verification
            (map-set peer-verifications
                { milestone-id: milestone-id, member: member, verifier: tx-sender }
                {
                    is-approved: is-approved,
                    feedback: feedback,
                    verification-date: u0
                }
            )
            
            ;; Update completion data
            (let
                ((new-verification-count (+ (get peer-verifications completion-data) u1)))
                (begin
                    (map-set milestone-completions
                        { milestone-id: milestone-id, member: member }
                        (merge completion-data {
                            peer-verifications: new-verification-count,
                            is-verified: (and is-approved (>= new-verification-count u2))
                        })
                    )
                    
                    ;; If verified, check if milestone is complete
                    (if (and is-approved (>= new-verification-count u2))
                        (check-milestone-completion milestone-id)
                        (ok true)
                    )
                )
            )
        )
    )
)

(define-private (check-milestone-completion (milestone-id uint))
    (let
        (
            (milestone-data (unwrap! (map-get? learning-milestones { milestone-id: milestone-id }) err-not-found))
            (new-completion-count (+ (get current-completions milestone-data) u1))
        )
        (begin
            (map-set learning-milestones
                { milestone-id: milestone-id }
                (merge milestone-data {
                    current-completions: new-completion-count,
                    is-completed: (>= new-completion-count (get required-completions milestone-data))
                })
            )
            
            ;; If milestone complete, update group
            (if (>= new-completion-count (get required-completions milestone-data))
                (update-group-milestone-completion (get group-id milestone-data))
                (ok true)
            )
        )
    )
)

(define-private (update-group-milestone-completion (group-id uint))
    (let
        (
            (group-data (unwrap! (map-get? study-groups { group-id: group-id }) err-not-found))
        )
        (begin
            (map-set study-groups
                { group-id: group-id }
                (merge group-data {
                    completed-milestones: (+ (get completed-milestones group-data) u1)
                })
            )
            (ok true)
        )
    )
)

(define-public (finalize-group (group-id uint))
    (let
        (
            (group-data (unwrap! (map-get? study-groups { group-id: group-id }) err-not-found))
            (completion-rate (if (> (get milestone-count group-data) u0)
                (/ (* (get completed-milestones group-data) u100) (get milestone-count group-data))
                u0
            ))
            (success-achieved (>= completion-rate (get success-threshold group-data)))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (is-group-organizer group-id) err-unauthorized)
            (asserts! (>= u0 (get end-block group-data)) err-invalid-input)
            
            ;; Update group status
            (map-set study-groups
                { group-id: group-id }
                (merge group-data {
                    status: (if success-achieved "completed" "failed")
                })
            )
            
            ;; Update subject stats
            (update-subject-stats (get subject group-data) false success-achieved)
            
            (ok success-achieved)
        )
    )
)

(define-public (claim-stake-return (group-id uint))
    (let
        (
            (group-data (unwrap! (map-get? study-groups { group-id: group-id }) err-not-found))
            (member-data (unwrap! (map-get? group-members { group-id: group-id, member: tx-sender }) err-not-found))
            (completion-rate (if (> (get milestone-count group-data) u0)
                (/ (* (get completed-milestones group-data) u100) (get milestone-count group-data))
                u0
            ))
            (success-achieved (>= completion-rate (get success-threshold group-data)))
            (stake-amount (get stake-amount member-data))
            (bonus-amount (if success-achieved
                (/ (* stake-amount (var-get completion-bonus-rate)) u10000)
                u0
            ))
            (total-return (+ stake-amount bonus-amount))
        )
        (begin
            (asserts! (not (var-get contract-paused)) err-contract-paused)
            (asserts! (or (is-eq (get status group-data) "completed") (is-eq (get status group-data) "failed")) err-group-closed)
            (asserts! (get is-active member-data) err-unauthorized)
            
            ;; Only return stake if group succeeded or individual participated
            (if (or success-achieved (> (get milestones-completed member-data) u0))
                (begin
                    (try! (as-contract (stx-transfer? total-return tx-sender tx-sender)))
                    
                    ;; Mark member as inactive
                    (map-set group-members
                        { group-id: group-id, member: tx-sender }
                        (merge member-data { is-active: false })
                    )
                    
                    ;; Update learner stats
                    (update-learner-completion-stats tx-sender total-return success-achieved)
                    
                    (ok total-return)
                )
                (ok u0)
            )
        )
    )
)

;; Helper Functions (Optimized)
(define-private (update-learner-stats (learner principal) (stake uint) (is-joining bool))
    (match (map-get? learner-profiles { learner: learner })
        profile (begin
            (map-set learner-profiles
                { learner: learner }
                (merge profile {
                    groups-joined: (if is-joining (+ (get groups-joined profile) u1) (get groups-joined profile)),
                    total-staked: (+ (get total-staked profile) stake)
                })
            )
            true
        )
        true
    )
)

(define-private (update-learner-completion-stats (learner principal) (earned uint) (success bool))
    (match (map-get? learner-profiles { learner: learner })
        profile (begin
            (map-set learner-profiles
                { learner: learner }
                (merge profile {
                    groups-completed: (+ (get groups-completed profile) u1),
                    total-earned: (+ (get total-earned profile) earned),
                    success-rate: (if success
                        (/ (* (+ (get groups-completed profile) u1) u100) (get groups-joined profile))
                        (get success-rate profile)
                    )
                })
            )
            true
        )
        true
    )
)

(define-private (update-subject-stats (subject (string-ascii 32)) (is-new bool) (is-success bool))
    (let
        (
            (stats (default-to 
                { total-groups: u0, completed-groups: u0, total-learners: u0, success-rate: u0 }
                (map-get? subject-stats { subject: subject })
            ))
        )
        (begin
            (map-set subject-stats
                { subject: subject }
                {
                    total-groups: (if is-new (+ (get total-groups stats) u1) (get total-groups stats)),
                    completed-groups: (if (and (not is-new) is-success) 
                        (+ (get completed-groups stats) u1) 
                        (get completed-groups stats)
                    ),
                    total-learners: (get total-learners stats),
                    success-rate: (if (and (not is-new) (> (get total-groups stats) u0))
                        (/ (* (get completed-groups stats) u100) (get total-groups stats))
                        (get success-rate stats)
                    )
                }
            )
            true
        )
    )
)

;; Optimized batch query functions
(define-public (get-multiple-groups (group-ids (list 20 uint)))
    (ok (map get-group-safe group-ids))
)

(define-private (get-group-safe (group-id uint))
    (map-get? study-groups { group-id: group-id })
)

;; Read-Only Functions
(define-read-only (get-study-group (group-id uint))
    (map-get? study-groups { group-id: group-id })
)

(define-read-only (get-group-member (group-id uint) (member principal))
    (map-get? group-members { group-id: group-id, member: member })
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? learning-milestones { milestone-id: milestone-id })
)

(define-read-only (get-milestone-completion (milestone-id uint) (member principal))
    (map-get? milestone-completions { milestone-id: milestone-id, member: member })
)

(define-read-only (get-learner-profile (learner principal))
    (map-get? learner-profiles { learner: learner })
)

(define-read-only (get-subject-stats (subject (string-ascii 32)))
    (map-get? subject-stats { subject: subject })
)

(define-read-only (get-contract-info)
    {
        next-group-id: (var-get next-group-id),
        next-milestone-id: (var-get next-milestone-id),
        min-stake-amount: (var-get min-stake-amount),
        platform-reward-pool: (var-get platform-reward-pool),
        completion-bonus-rate: (var-get completion-bonus-rate),
        is-paused: (var-get contract-paused)
    }
)

;; Emergency Functions
(define-public (emergency-withdraw)
    (begin
        (asserts! (is-owner) err-owner-only)
        (asserts! (var-get contract-paused) err-unauthorized)
        (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender contract-owner))
    )
)