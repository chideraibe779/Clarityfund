;; ---------------------------------------------------------
;; Contract: CrowdFundX
;; Purpose: Decentralized Community Crowdfunding Vault
;; ---------------------------------------------------------

(define-constant ERR_CAMPAIGN_NOT_FOUND (err u100))
(define-constant ERR_ALREADY_FUNDED (err u101))
(define-constant ERR_DEADLINE_PASSED (err u102))
(define-constant ERR_GOAL_NOT_REACHED (err u103))
(define-constant ERR_NOT_CREATOR (err u104))
(define-constant ERR_NOTHING_TO_REFUND (err u105))

;; ----------------------------
;; Campaign Structure
;; ----------------------------
(define-map campaigns
  { id: uint }
  {
    creator: principal,
    goal: uint,
    deadline: uint,
    raised: uint,
    successful: bool
  })

;; Tracks contributions: (campaign-id, user) -> amount
(define-map contributions
  { id: uint, user: principal }
  { amount: uint })

(define-data-var next-campaign-id uint u0)

;; ----------------------------
;; Create a new campaign
;; ----------------------------
(define-public (create-campaign (goal uint) (duration uint))
  (let ((id (var-get next-campaign-id)))
    (map-set campaigns { id: id }
      {
        creator: tx-sender,
        goal: goal,
        deadline: (+ stacks-block-height duration),
        raised: u0,
        successful: false
      })
    (var-set next-campaign-id (+ id u1))
    (ok id)))

;; ----------------------------
;; Contribute STX to a campaign
;; ----------------------------
(define-public (contribute (id uint) (amount uint))
  (let ((campaign (unwrap! (map-get? campaigns { id: id }) ERR_CAMPAIGN_NOT_FOUND)))
    (asserts! (< stacks-block-height (get deadline campaign)) ERR_DEADLINE_PASSED)
    
    ;; Handle transfer first
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (begin
      ;; Update contribution record
      (let ((existing-contribution (default-to u0 (get amount (map-get? contributions { id: id, user: tx-sender })))))
        (map-set contributions { id: id, user: tx-sender } 
          { amount: (+ amount existing-contribution) }))
      
      ;; Update campaign total
      (map-set campaigns { id: id }
        (merge campaign { raised: (+ (get raised campaign) amount) }))
      
      (ok true))))

;; ----------------------------
;; Finalize campaign
;; ----------------------------
(define-public (finalize-campaign (id uint))
  (let ((campaign (unwrap! (map-get? campaigns { id: id }) ERR_CAMPAIGN_NOT_FOUND)))
    (asserts! (>= (get raised campaign) (get goal campaign)) ERR_GOAL_NOT_REACHED)
    (begin
      (map-set campaigns { id: id }
        (merge campaign { successful: true }))
      (ok true))))

;; ----------------------------
;; Withdraw funds
;; ----------------------------
(define-public (withdraw (id uint))
  (let ((campaign (unwrap! (map-get? campaigns { id: id }) ERR_CAMPAIGN_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator campaign)) ERR_NOT_CREATOR)
    (asserts! (get successful campaign) ERR_GOAL_NOT_REACHED)
    
    (let ((amount (get raised campaign)))
      (map-set campaigns { id: id } (merge campaign { raised: u0 }))
      (as-contract (stx-transfer? amount tx-sender (get creator campaign))))))

;; ----------------------------
;; Refund supporter
;; ----------------------------
(define-public (refund (id uint))
  (let (
    (campaign (unwrap! (map-get? campaigns { id: id }) ERR_CAMPAIGN_NOT_FOUND))
    (contrib (unwrap! (map-get? contributions { id: id, user: tx-sender }) ERR_NOTHING_TO_REFUND))
  )
    ;; Refund only if deadline passed AND campaign failed
    (asserts! (>= stacks-block-height (get deadline campaign)) ERR_DEADLINE_PASSED)
    (asserts! (not (get successful campaign)) ERR_ALREADY_FUNDED)
    
    (let ((amt (get amount contrib)))
      (asserts! (> amt u0) ERR_NOTHING_TO_REFUND)
      (begin
        (map-delete contributions { id: id, user: tx-sender })
        (as-contract (stx-transfer? amt tx-sender (get user { id: id, user: tx-sender })))))))

;; ----------------------------
;; View Functions
;; ----------------------------
(define-read-only (get-campaign (id uint))
  (map-get? campaigns { id: id }))

(define-read-only (get-contribution (id uint) (user principal))
  (map-get? contributions { id: id, user: user }))