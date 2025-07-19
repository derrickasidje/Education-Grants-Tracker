(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-GRANT-NOT-FOUND (err u102))
(define-constant ERR-MILESTONE-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-MILESTONE-NOT-DUE (err u105))
(define-constant ERR-INSUFFICIENT-VOTES (err u106))

(define-data-var contract-owner principal tx-sender)
(define-data-var min-approval-threshold uint u3)
(define-data-var next-grant-id uint u1)
(define-data-var next-milestone-id uint u1)

(define-map Grants 
    uint 
    {
        recipient: principal,
        total-amount: uint,
        remaining-amount: uint,
        status: (string-ascii 20),
        created-at: uint
    }
)

(define-map Milestones
    uint 
    {
        grant-id: uint,
        amount: uint,
        due-date: uint,
        completed: bool,
        approval-count: uint,
        rejection-count: uint
    }
)

(define-map GrantMilestones
    uint
    (list 10 uint)
)

(define-map VoteRegistry
    {milestone-id: uint, voter: principal}
    bool
)

(define-read-only (get-grant (grant-id uint))
    (map-get? Grants grant-id)
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? Milestones milestone-id)
)

(define-read-only (get-grant-milestones (grant-id uint))
    (map-get? GrantMilestones grant-id)
)

(define-public (create-grant (recipient principal) (total-amount uint))
    (let
        (
            (grant-id (var-get next-grant-id))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set Grants grant-id {
            recipient: recipient,
            total-amount: total-amount,
            remaining-amount: total-amount,
            status: "ACTIVE",
            created-at: stacks-block-height
        })
        
        (map-set GrantMilestones grant-id (list))
        (var-set next-grant-id (+ grant-id u1))
        (ok grant-id)
    )
)

(define-public (add-milestone (grant-id uint) (amount uint) (due-date uint))
    (let
        (
            (milestone-id (var-get next-milestone-id))
            (grant (unwrap! (get-grant grant-id) ERR-GRANT-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= amount (get remaining-amount grant)) ERR-INVALID-AMOUNT)
        
        (map-set Milestones milestone-id {
            grant-id: grant-id,
            amount: amount,
            due-date: due-date,
            completed: false,
            approval-count: u0,
            rejection-count: u0
        })
        
        (map-set GrantMilestones 
            grant-id 
            (unwrap-panic (as-max-len? 
                (append (default-to (list) (get-grant-milestones grant-id)) milestone-id) 
                u10
            ))
        )
        
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (submit-milestone-completion (milestone-id uint))
    (let
        (
            (milestone (unwrap! (get-milestone milestone-id) ERR-MILESTONE-NOT-FOUND))
            (grant (unwrap! (get-grant (get grant-id milestone)) ERR-GRANT-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! (>= stacks-block-height (get due-date milestone)) ERR-MILESTONE-NOT-DUE)
        
        (map-set Milestones milestone-id (merge milestone {completed: true}))
        (ok true)
    )
)

(define-public (vote-on-milestone (milestone-id uint) (approve bool))
    (let
        (
            (milestone (unwrap! (get-milestone milestone-id) ERR-MILESTONE-NOT-FOUND))
            (vote-key {milestone-id: milestone-id, voter: tx-sender})
        )
        (asserts! (not (default-to false (map-get? VoteRegistry vote-key))) ERR-ALREADY-VOTED)
        
        (map-set VoteRegistry vote-key true)
        (if approve
            (map-set Milestones milestone-id (merge milestone {approval-count: (+ (get approval-count milestone) u1)}))
            (map-set Milestones milestone-id (merge milestone {rejection-count: (+ (get rejection-count milestone) u1)}))
        )
        (ok true)
    )
)

(define-public (release-milestone-funds (milestone-id uint))
    (let
        (
            (milestone (unwrap! (get-milestone milestone-id) ERR-MILESTONE-NOT-FOUND))
            (grant (unwrap! (get-grant (get grant-id milestone)) ERR-GRANT-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (get approval-count milestone) (var-get min-approval-threshold)) ERR-INSUFFICIENT-VOTES)
        
        (try! (stx-transfer? (get amount milestone) tx-sender (get recipient grant)))
        (map-set Grants (get grant-id milestone) 
            (merge grant {remaining-amount: (- (get remaining-amount grant) (get amount milestone))})
        )
        (ok true)
    )
)

(define-public (update-approval-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set min-approval-threshold new-threshold)
        (ok true)
    )
)
