(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-GRANT-NOT-FOUND (err u102))
(define-constant ERR-MILESTONE-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-MILESTONE-NOT-DUE (err u105))
(define-constant ERR-INSUFFICIENT-VOTES (err u106))
(define-constant ERR-INVALID-TIMEFRAME (err u107))
(define-constant ERR-RENEWAL-NOT-FOUND (err u108))
(define-constant ERR-RENEWAL-ALREADY-EXISTS (err u109))
(define-constant ERR-PERFORMANCE-TOO-LOW (err u110))
(define-constant ERR-GRANT-NOT-COMPLETED (err u111))

(define-data-var contract-owner principal tx-sender)
(define-data-var min-approval-threshold uint u3)
(define-data-var next-grant-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-renewal-id uint u1)
(define-data-var min-performance-score uint u70)
(define-data-var auto-renewal-enabled bool true)

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

(define-map GrantAnalytics
    uint
    {
        completion-rate: uint,
        avg-voting-time: uint,
        total-disbursed: uint,
        milestones-completed: uint,
        milestones-rejected: uint,
        performance-score: uint
    }
)

(define-map RecipientStats
    principal
    {
        total-grants-received: uint,
        total-amount-received: uint,
        successful-milestones: uint,
        failed-milestones: uint,
        avg-completion-time: uint
    }
)

(define-map PlatformMetrics
    (string-ascii 20)
    uint
)

(define-map GrantRenewals
    uint
    {
        original-grant-id: uint,
        recipient: principal,
        requested-amount: uint,
        justification: (string-ascii 500),
        status: (string-ascii 20),
        applied-at: uint,
        auto-approved: bool,
        performance-score-at-application: uint
    }
)

(define-map RenewalRequests
    {grant-id: uint}
    uint
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

(define-read-only (get-grant-analytics (grant-id uint))
    (map-get? GrantAnalytics grant-id)
)

(define-read-only (get-recipient-stats (recipient principal))
    (map-get? RecipientStats recipient)
)

(define-read-only (get-platform-metric (metric-name (string-ascii 20)))
    (default-to u0 (map-get? PlatformMetrics metric-name))
)

(define-read-only (get-renewal-request (renewal-id uint))
    (map-get? GrantRenewals renewal-id)
)

(define-read-only (get-grant-renewal-status (grant-id uint))
    (map-get? RenewalRequests {grant-id: grant-id})
)

(define-read-only (check-renewal-eligibility (grant-id uint))
    (let
        (
            (grant (unwrap! (get-grant grant-id) ERR-GRANT-NOT-FOUND))
            (performance-result (unwrap-panic (calculate-grant-performance-score grant-id)))
        )
        (ok {
            eligible: (and 
                (is-eq (get status grant) "ACTIVE")
                (>= performance-result (var-get min-performance-score))
                (is-eq (get remaining-amount grant) u0)
            ),
            performance-score: performance-result,
            min-required-score: (var-get min-performance-score)
        })
    )
)

(define-read-only (calculate-grant-performance-score (grant-id uint))
    (let
        (
            (grant (unwrap! (get-grant grant-id) (ok u0)))
            (analytics (default-to 
                {completion-rate: u0, avg-voting-time: u0, total-disbursed: u0, 
                 milestones-completed: u0, milestones-rejected: u0, performance-score: u0}
                (get-grant-analytics grant-id)
            ))
            (completion-rate (get completion-rate analytics))
            (voting-efficiency (if (> (get avg-voting-time analytics) u0) 
                (/ u10000 (get avg-voting-time analytics)) u0))
            (disbursement-ratio (if (> (get total-amount grant) u0)
                (/ (* (get total-disbursed analytics) u100) (get total-amount grant)) u0))
        )
        (ok (/ (+ completion-rate voting-efficiency disbursement-ratio) u3))
    )
)

(define-read-only (get-platform-summary)
    (ok {
        total-grants: (get-platform-metric "total-grants"),
        total-disbursed: (get-platform-metric "total-disbursed"),
        avg-success-rate: (get-platform-metric "avg-success-rate"),
        active-recipients: (get-platform-metric "active-recipients")
    })
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
        
        (map-set GrantAnalytics grant-id {
            completion-rate: u0,
            avg-voting-time: u0,
            total-disbursed: u0,
            milestones-completed: u0,
            milestones-rejected: u0,
            performance-score: u0
        })
        
        (update-recipient-stats recipient total-amount u0 u0 u0)
        (increment-platform-metric "total-grants")
        
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
        
        (update-grant-analytics-on-release (get grant-id milestone) (get amount milestone))
        (update-recipient-stats-on-release (get recipient grant) (get amount milestone))
        (increment-platform-metric "total-disbursed")
        
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

(define-public (apply-for-grant-renewal (grant-id uint) (requested-amount uint) (justification (string-ascii 500)))
    (let
        (
            (renewal-id (var-get next-renewal-id))
            (grant (unwrap! (get-grant grant-id) ERR-GRANT-NOT-FOUND))
            (eligibility (unwrap-panic (check-renewal-eligibility grant-id)))
            (existing-renewal (get-grant-renewal-status grant-id))
            (performance-score (get performance-score eligibility))
            (is-eligible (get eligible eligibility))
            (should-auto-approve (and 
                (var-get auto-renewal-enabled)
                is-eligible
                (>= performance-score (var-get min-performance-score))
            ))
        )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! is-eligible ERR-PERFORMANCE-TOO-LOW)
        (asserts! (is-none existing-renewal) ERR-RENEWAL-ALREADY-EXISTS)
        (asserts! (> requested-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set GrantRenewals renewal-id {
            original-grant-id: grant-id,
            recipient: (get recipient grant),
            requested-amount: requested-amount,
            justification: justification,
            status: (if should-auto-approve "APPROVED" "PENDING"),
            applied-at: stacks-block-height,
            auto-approved: should-auto-approve,
            performance-score-at-application: performance-score
        })
        
        (map-set RenewalRequests {grant-id: grant-id} renewal-id)
        (var-set next-renewal-id (+ renewal-id u1))
        
        (if should-auto-approve
            (begin
                (try! (create-grant (get recipient grant) requested-amount))
                (ok {renewal-id: renewal-id, auto-approved: true})
            )
            (ok {renewal-id: renewal-id, auto-approved: false})
        )
    )
)

(define-public (approve-renewal-request (renewal-id uint))
    (let
        (
            (renewal (unwrap! (get-renewal-request renewal-id) ERR-RENEWAL-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status renewal) "PENDING") ERR-NOT-AUTHORIZED)
        
        (map-set GrantRenewals renewal-id (merge renewal {status: "APPROVED"}))
        (try! (create-grant (get recipient renewal) (get requested-amount renewal)))
        (ok true)
    )
)

(define-public (reject-renewal-request (renewal-id uint))
    (let
        (
            (renewal (unwrap! (get-renewal-request renewal-id) ERR-RENEWAL-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status renewal) "PENDING") ERR-NOT-AUTHORIZED)
        
        (map-set GrantRenewals renewal-id (merge renewal {status: "REJECTED"}))
        (ok true)
    )
)

(define-public (configure-renewal-settings (auto-renewal bool) (min-score uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= min-score u100) ERR-INVALID-AMOUNT)
        
        (var-set auto-renewal-enabled auto-renewal)
        (var-set min-performance-score min-score)
        (ok true)
    )
)

(define-private (update-recipient-stats (recipient principal) (amount-change uint) (successful-milestones uint) (failed-milestones uint) (completion-time uint))
    (let
        (
            (current-stats (default-to 
                {total-grants-received: u0, total-amount-received: u0, successful-milestones: u0, 
                 failed-milestones: u0, avg-completion-time: u0}
                (get-recipient-stats recipient)
            ))
            (new-total-grants (+ (get total-grants-received current-stats) u1))
            (new-total-amount (+ (get total-amount-received current-stats) amount-change))
            (new-successful (+ (get successful-milestones current-stats) successful-milestones))
            (new-failed (+ (get failed-milestones current-stats) failed-milestones))
            (new-avg-time (if (> new-successful u0)
                (/ (+ (* (get avg-completion-time current-stats) (get successful-milestones current-stats)) 
                      (* completion-time successful-milestones)) new-successful)
                (get avg-completion-time current-stats)))
        )
        (map-set RecipientStats recipient {
            total-grants-received: new-total-grants,
            total-amount-received: new-total-amount,
            successful-milestones: new-successful,
            failed-milestones: new-failed,
            avg-completion-time: new-avg-time
        })
    )
)

(define-private (update-recipient-stats-on-release (recipient principal) (amount uint))
    (let
        (
            (current-stats (default-to 
                {total-grants-received: u0, total-amount-received: u0, successful-milestones: u0, 
                 failed-milestones: u0, avg-completion-time: u0}
                (get-recipient-stats recipient)
            ))
        )
        (map-set RecipientStats recipient 
            (merge current-stats {
                total-amount-received: (+ (get total-amount-received current-stats) amount),
                successful-milestones: (+ (get successful-milestones current-stats) u1)
            })
        )
    )
)

(define-private (update-grant-analytics-on-release (grant-id uint) (amount uint))
    (let
        (
            (current-analytics (default-to 
                {completion-rate: u0, avg-voting-time: u0, total-disbursed: u0, 
                 milestones-completed: u0, milestones-rejected: u0, performance-score: u0}
                (get-grant-analytics grant-id)
            ))
            (new-disbursed (+ (get total-disbursed current-analytics) amount))
            (new-completed (+ (get milestones-completed current-analytics) u1))
            (total-milestones (+ new-completed (get milestones-rejected current-analytics)))
            (new-completion-rate (if (> total-milestones u0) 
                (/ (* new-completed u100) total-milestones) u0))
        )
        (map-set GrantAnalytics grant-id 
            (merge current-analytics {
                completion-rate: new-completion-rate,
                total-disbursed: new-disbursed,
                milestones-completed: new-completed
            })
        )
    )
)

(define-private (increment-platform-metric (metric-name (string-ascii 20)))
    (let
        (
            (current-value (get-platform-metric metric-name))
        )
        (map-set PlatformMetrics metric-name (+ current-value u1))
    )
)

(define-public (generate-analytics-report (grant-id uint))
    (let
        (
            (grant (unwrap! (get-grant grant-id) ERR-GRANT-NOT-FOUND))
            (analytics (unwrap! (get-grant-analytics grant-id) ERR-GRANT-NOT-FOUND))
            (milestones (default-to (list) (get-grant-milestones grant-id)))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        
        (ok {
            grant-status: (get status grant),
            total-amount: (get total-amount grant),
            disbursed-amount: (get total-disbursed analytics),
            completion-rate: (get completion-rate analytics),
            milestones-count: (len milestones),
            performance-score: (unwrap-panic (calculate-grant-performance-score grant-id))
        })
    )
)

(define-public (get-recipient-performance-report (recipient principal) (timeframe-start uint) (timeframe-end uint))
    (let
        (
            (stats (default-to 
                {total-grants-received: u0, total-amount-received: u0, successful-milestones: u0, 
                 failed-milestones: u0, avg-completion-time: u0}
                (get-recipient-stats recipient)
            ))
        )
        (asserts! (< timeframe-start timeframe-end) ERR-INVALID-TIMEFRAME)
        
        (ok {
            recipient: recipient,
            grants-received: (get total-grants-received stats),
            total-funding: (get total-amount-received stats),
            success-rate: (if (> (+ (get successful-milestones stats) (get failed-milestones stats)) u0)
                (/ (* (get successful-milestones stats) u100) 
                   (+ (get successful-milestones stats) (get failed-milestones stats))) u0),
            avg-delivery-time: (get avg-completion-time stats)
        })
    )
)
