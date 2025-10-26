(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-rented (err u102))
(define-constant err-not-rented (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-rental-expired (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-invalid-duration (err u107))
(define-constant err-outfit-not-available (err u108))
(define-constant err-already-reviewed (err u109))
(define-constant err-rental-not-completed (err u110))
(define-constant err-invalid-rating (err u111))
(define-constant err-invalid-surge-rate (err u112))
(define-constant err-cooldown-period (err u113))
(define-constant err-invalid-deposit (err u114))
(define-constant err-insufficient-balance (err u115))
(define-constant err-no-rewards (err u116))

(define-data-var next-outfit-id uint u1)
(define-data-var next-rental-id uint u1)
(define-data-var next-review-id uint u1)
(define-data-var platform-fee-percentage uint u5)
(define-data-var current-time uint u0)
(define-data-var surge-threshold uint u3)
(define-data-var surge-multiplier uint u150)
(define-data-var discount-threshold uint u7)
(define-data-var discount-percentage uint u80)
(define-data-var price-update-cooldown uint u24)
(define-data-var loyalty-reward-percentage uint u10)

(define-map outfits
  { outfit-id: uint }
  {
    name: (string-utf8 64),
    description: (string-utf8 256),
    image-uri: (string-utf8 256),
    owner: principal,
    rental-price-per-hour: uint,
    available: bool,
    category: (string-utf8 32)
  }
)

(define-map rentals
  { rental-id: uint }
  {
    outfit-id: uint,
    renter: principal,
    start-time: uint,
    end-time: uint,
    total-cost: uint,
    active: bool
  }
)

(define-map user-active-rentals
  { user: principal }
  { rental-ids: (list 50 uint) }
)

(define-map outfit-rental-history
  { outfit-id: uint }
  { rental-count: uint, total-revenue: uint }
)

(define-map outfit-reviews
  { review-id: uint }
  {
    outfit-id: uint,
    rental-id: uint,
    reviewer: principal,
    rating: uint,
    comment: (string-utf8 512),
    review-time: uint
  }
)

(define-map outfit-ratings
  { outfit-id: uint }
  {
    total-ratings: uint,
    sum-ratings: uint,
    average-rating: uint
  }
)

(define-map rental-reviews
  { rental-id: uint }
  { review-id: uint }
)

(define-map outfit-demand-metrics
  { outfit-id: uint }
  {
    recent-rental-count: uint,
    last-rental-time: uint,
    price-tier: uint,
    surge-active: bool,
    discount-active: bool,
    last-price-update: uint
  }
)

(define-map outfit-price-history
  { outfit-id: uint, timestamp: uint }
  {
    base-price: uint,
    adjusted-price: uint,
    adjustment-type: (string-utf8 16)
  }
)

(define-map weekly-rental-tracker
  { outfit-id: uint, week-number: uint }
  { rental-count: uint }
)

(define-map user-loyalty-wallet
  { user: principal }
  { balance: uint, total-earned: uint, last-updated: uint }
)

(define-map user-rental-count
  { user: principal }
  { count: uint }
)

(define-private (get-current-week)
  (/ (var-get current-time) u168)
)

(define-private (update-demand-metrics (outfit-id uint))
  (let (
    (current-week (get-current-week))
    (metrics (default-to
      {
        recent-rental-count: u0,
        last-rental-time: u0,
        price-tier: u1,
        surge-active: false,
        discount-active: false,
        last-price-update: u0
      }
      (map-get? outfit-demand-metrics { outfit-id: outfit-id })))
    (weekly-rentals (default-to { rental-count: u0 }
      (map-get? weekly-rental-tracker { outfit-id: outfit-id, week-number: current-week })))
    (new-rental-count (+ (get rental-count weekly-rentals) u1))
  )
    (map-set weekly-rental-tracker
      { outfit-id: outfit-id, week-number: current-week }
      { rental-count: new-rental-count }
    )
    
    (let (
      (should-surge (>= new-rental-count (var-get surge-threshold)))
      (should-discount (and 
        (< new-rental-count u2)
        (>= (- (var-get current-time) (get last-rental-time metrics)) (var-get discount-threshold))
      ))
    )
      (map-set outfit-demand-metrics
        { outfit-id: outfit-id }
        {
          recent-rental-count: new-rental-count,
          last-rental-time: (var-get current-time),
          price-tier: (if should-surge u3 (if should-discount u0 u1)),
          surge-active: should-surge,
          discount-active: should-discount,
          last-price-update: (var-get current-time)
        }
      )
    )
    (ok true)
  )
)

(define-read-only (get-dynamic-price (outfit-id uint))
  (let (
    (outfit (unwrap! (map-get? outfits { outfit-id: outfit-id }) none))
    (base-price (get rental-price-per-hour outfit))
    (metrics (default-to
      {
        recent-rental-count: u0,
        last-rental-time: u0,
        price-tier: u1,
        surge-active: false,
        discount-active: false,
        last-price-update: u0
      }
      (map-get? outfit-demand-metrics { outfit-id: outfit-id })))
  )
    (if (get surge-active metrics)
      (some (/ (* base-price (var-get surge-multiplier)) u100))
      (if (get discount-active metrics)
        (some (/ (* base-price (var-get discount-percentage)) u100))
        (some base-price)
      )
    )
  )
)

(define-private (remove-rental-id (id uint))
  (not (is-eq id (var-get next-rental-id)))
)

(define-public (create-outfit 
  (name (string-utf8 64))
  (description (string-utf8 256))
  (image-uri (string-utf8 256))
  (rental-price-per-hour uint)
  (category (string-utf8 32))
)
  (let ((outfit-id (var-get next-outfit-id)))
    (map-set outfits
      { outfit-id: outfit-id }
      {
        name: name,
        description: description,
        image-uri: image-uri,
        owner: tx-sender,
        rental-price-per-hour: rental-price-per-hour,
        available: true,
        category: category
      }
    )
    (map-set outfit-demand-metrics
      { outfit-id: outfit-id }
      {
        recent-rental-count: u0,
        last-rental-time: u0,
        price-tier: u1,
        surge-active: false,
        discount-active: false,
        last-price-update: (var-get current-time)
      }
    )
    (var-set next-outfit-id (+ outfit-id u1))
    (ok outfit-id)
  )
)

(define-public (rent-outfit (outfit-id uint) (duration-hours uint))
  (let (
    (outfit (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found))
    (rental-id (var-get next-rental-id))
    (current-timestamp (var-get current-time))
    (end-timestamp (+ current-timestamp duration-hours))
    (dynamic-price (unwrap! (get-dynamic-price outfit-id) err-not-found))
    (total-cost (* dynamic-price duration-hours))
    (platform-fee (/ (* total-cost (var-get platform-fee-percentage)) u100))
    (owner-payment (- total-cost platform-fee))
  )
    (asserts! (get available outfit) err-outfit-not-available)
    (asserts! (> duration-hours u0) err-invalid-duration)
    (asserts! (>= (stx-get-balance tx-sender) total-cost) err-insufficient-payment)
    
    (try! (stx-transfer? owner-payment tx-sender (get owner outfit)))
    (try! (stx-transfer? platform-fee tx-sender contract-owner))
    
    (map-set outfits
      { outfit-id: outfit-id }
      (merge outfit { available: false })
    )
    
    (map-set rentals
      { rental-id: rental-id }
      {
        outfit-id: outfit-id,
        renter: tx-sender,
        start-time: current-timestamp,
        end-time: end-timestamp,
        total-cost: total-cost,
        active: true
      }
    )
    
    (let ((user-rentals (default-to { rental-ids: (list) } 
                                   (map-get? user-active-rentals { user: tx-sender }))))
      (map-set user-active-rentals
        { user: tx-sender }
        { rental-ids: (unwrap! (as-max-len? (append (get rental-ids user-rentals) rental-id) u50) err-owner-only) }
      )
    )
    
    (let ((history (default-to { rental-count: u0, total-revenue: u0 } 
                               (map-get? outfit-rental-history { outfit-id: outfit-id }))))
      (map-set outfit-rental-history
        { outfit-id: outfit-id }
        { 
          rental-count: (+ (get rental-count history) u1),
          total-revenue: (+ (get total-revenue history) total-cost)
        }
      )
    )
    
    (unwrap! (update-demand-metrics outfit-id) err-not-found)
    
    (let (
      (user-rentals-data (default-to { count: u0 } (map-get? user-rental-count { user: tx-sender })))
      (new-count (+ (get count user-rentals-data) u1))
      (reward-amount (/ (* total-cost (var-get loyalty-reward-percentage)) u100))
      (wallet (default-to { balance: u0, total-earned: u0, last-updated: u0 } 
                          (map-get? user-loyalty-wallet { user: tx-sender })))
    )
      (map-set user-rental-count
        { user: tx-sender }
        { count: new-count }
      )
      (map-set user-loyalty-wallet
        { user: tx-sender }
        {
          balance: (+ (get balance wallet) reward-amount),
          total-earned: (+ (get total-earned wallet) reward-amount),
          last-updated: (var-get current-time)
        }
      )
    )
    
    (var-set next-rental-id (+ rental-id u1))
    (ok rental-id)
  )
)

(define-public (return-outfit (rental-id uint))
  (let (
    (rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found))
    (outfit-id (get outfit-id rental))
  )
    (asserts! (is-eq tx-sender (get renter rental)) err-unauthorized)
    (asserts! (get active rental) err-not-rented)
    
    (map-set rentals
      { rental-id: rental-id }
      (merge rental { active: false })
    )
    
    (map-set outfits
      { outfit-id: outfit-id }
      (merge (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found) 
             { available: true })
    )
    
    (let ((user-rentals (unwrap! (map-get? user-active-rentals { user: tx-sender }) err-not-found)))
      (map-set user-active-rentals
        { user: tx-sender }
        { rental-ids: (filter remove-rental-id (get rental-ids user-rentals)) }
      )
    )
    
    (ok true)
  )
)

(define-public (force-return-expired-outfit (rental-id uint))
  (let (
    (rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found))
    (outfit-id (get outfit-id rental))
    (current-timestamp (var-get current-time))
  )
    (asserts! (get active rental) err-not-rented)
    (asserts! (>= current-timestamp (get end-time rental)) err-rental-expired)
    
    (map-set rentals
      { rental-id: rental-id }
      (merge rental { active: false })
    )
    
    (map-set outfits
      { outfit-id: outfit-id }
      (merge (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found) 
             { available: true })
    )
    
    (let ((user-rentals (unwrap! (map-get? user-active-rentals { user: (get renter rental) }) err-not-found)))
      (map-set user-active-rentals
        { user: (get renter rental) }
        { rental-ids: (filter remove-rental-id (get rental-ids user-rentals)) }
      )
    )
    
    (ok true)
  )
)

(define-public (update-outfit-price (outfit-id uint) (new-price uint))
  (let ((outfit (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get owner outfit)) err-unauthorized)
    (asserts! (get available outfit) err-already-rented)
    
    (map-set outfits
      { outfit-id: outfit-id }
      (merge outfit { rental-price-per-hour: new-price })
    )
    
    (ok true)
  )
)

(define-public (toggle-outfit-availability (outfit-id uint))
  (let ((outfit (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get owner outfit)) err-unauthorized)
    
    (map-set outfits
      { outfit-id: outfit-id }
      (merge outfit { available: (not (get available outfit)) })
    )
    
    (ok true)
  )
)

(define-public (advance-time (hours uint))
  (begin
    (var-set current-time (+ (var-get current-time) hours))
    (ok (var-get current-time))
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u20) err-owner-only)
    (var-set platform-fee-percentage new-fee)
    (ok true)
  )
)

(define-public (submit-review (rental-id uint) (rating uint) (comment (string-utf8 512)))
  (let (
    (rental (unwrap! (map-get? rentals { rental-id: rental-id }) err-not-found))
    (review-id (var-get next-review-id))
    (outfit-id (get outfit-id rental))
    (current-timestamp (var-get current-time))
  )
    (asserts! (is-eq tx-sender (get renter rental)) err-unauthorized)
    (asserts! (not (get active rental)) err-rental-not-completed)
    (asserts! (is-none (map-get? rental-reviews { rental-id: rental-id })) err-already-reviewed)
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
    
    (map-set outfit-reviews
      { review-id: review-id }
      {
        outfit-id: outfit-id,
        rental-id: rental-id,
        reviewer: tx-sender,
        rating: rating,
        comment: comment,
        review-time: current-timestamp
      }
    )
    
    (map-set rental-reviews
      { rental-id: rental-id }
      { review-id: review-id }
    )
    
    (let ((current-ratings (default-to { total-ratings: u0, sum-ratings: u0, average-rating: u0 } 
                                      (map-get? outfit-ratings { outfit-id: outfit-id }))))
      (let (
        (new-total (+ (get total-ratings current-ratings) u1))
        (new-sum (+ (get sum-ratings current-ratings) rating))
      )
        (map-set outfit-ratings
          { outfit-id: outfit-id }
          {
            total-ratings: new-total,
            sum-ratings: new-sum,
            average-rating: (/ (* new-sum u100) new-total)
          }
        )
      )
    )
    
    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

(define-read-only (get-outfit (outfit-id uint))
  (map-get? outfits { outfit-id: outfit-id })
)

(define-read-only (get-rental (rental-id uint))
  (map-get? rentals { rental-id: rental-id })
)

(define-read-only (get-user-active-rentals (user principal))
  (map-get? user-active-rentals { user: user })
)

(define-read-only (get-outfit-history (outfit-id uint))
  (map-get? outfit-rental-history { outfit-id: outfit-id })
)

(define-read-only (is-rental-expired (rental-id uint))
  (match (map-get? rentals { rental-id: rental-id })
    rental (>= (var-get current-time) (get end-time rental))
    false
  )
)

(define-read-only (get-rental-time-remaining (rental-id uint))
  (match (map-get? rentals { rental-id: rental-id })
    rental 
      (if (>= (var-get current-time) (get end-time rental))
        u0
        (- (get end-time rental) (var-get current-time))
      )
    u0
  )
)

(define-read-only (calculate-rental-cost (outfit-id uint) (duration-hours uint))
  (match (map-get? outfits { outfit-id: outfit-id })
    outfit 
      (let ((total-cost (* (get rental-price-per-hour outfit) duration-hours)))
        (some {
          total-cost: total-cost,
          platform-fee: (/ (* total-cost (var-get platform-fee-percentage)) u100),
          owner-payment: (- total-cost (/ (* total-cost (var-get platform-fee-percentage)) u100))
        })
      )
    none
  )
)

(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

(define-read-only (get-current-time)
  (var-get current-time)
)

(define-read-only (get-next-outfit-id)
  (var-get next-outfit-id)
)

(define-read-only (get-next-rental-id)
  (var-get next-rental-id)
)

(define-read-only (get-review (review-id uint))
  (map-get? outfit-reviews { review-id: review-id })
)

(define-read-only (get-outfit-rating (outfit-id uint))
  (map-get? outfit-ratings { outfit-id: outfit-id })
)

(define-read-only (get-rental-review (rental-id uint))
  (match (map-get? rental-reviews { rental-id: rental-id })
    review-data (map-get? outfit-reviews { review-id: (get review-id review-data) })
    none
  )
)

(define-read-only (get-next-review-id)
  (var-get next-review-id)
)


(define-public (trigger-price-update (outfit-id uint))
  (let (
    (outfit (unwrap! (map-get? outfits { outfit-id: outfit-id }) err-not-found))
    (metrics (unwrap! (map-get? outfit-demand-metrics { outfit-id: outfit-id }) err-not-found))
    (current-timestamp (var-get current-time))
    (time-since-update (- current-timestamp (get last-price-update metrics)))
  )
    (asserts! (is-eq tx-sender (get owner outfit)) err-unauthorized)
    (asserts! (>= time-since-update (var-get price-update-cooldown)) err-cooldown-period)
    
    (let (
      (current-week (get-current-week))
      (weekly-rentals (default-to { rental-count: u0 }
        (map-get? weekly-rental-tracker { outfit-id: outfit-id, week-number: current-week })))
      (rental-count (get rental-count weekly-rentals))
      (should-surge (>= rental-count (var-get surge-threshold)))
      (days-since-rental (/ (- current-timestamp (get last-rental-time metrics)) u24))
      (should-discount (and (< rental-count u2) (>= days-since-rental (var-get discount-threshold))))
      (new-tier (if should-surge u3 (if should-discount u0 u1)))
    )
      (map-set outfit-demand-metrics
        { outfit-id: outfit-id }
        (merge metrics {
          price-tier: new-tier,
          surge-active: should-surge,
          discount-active: should-discount,
          last-price-update: current-timestamp
        })
      )
      
      (let (
        (base-price (get rental-price-per-hour outfit))
        (adjusted-price (if should-surge
          (/ (* base-price (var-get surge-multiplier)) u100)
          (if should-discount
            (/ (* base-price (var-get discount-percentage)) u100)
            base-price)))
        (adjustment-type (if should-surge u"surge" (if should-discount u"discount" u"normal")))
      )
        (map-set outfit-price-history
          { outfit-id: outfit-id, timestamp: current-timestamp }
          {
            base-price: base-price,
            adjusted-price: adjusted-price,
            adjustment-type: adjustment-type
          }
        )
      )
      (ok true)
    )
  )
)

(define-public (set-surge-parameters (threshold uint) (multiplier uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (> threshold u0) (<= threshold u10)) err-invalid-surge-rate)
    (asserts! (and (>= multiplier u100) (<= multiplier u300)) err-invalid-surge-rate)
    (var-set surge-threshold threshold)
    (var-set surge-multiplier multiplier)
    (ok true)
  )
)

(define-public (set-discount-parameters (threshold-days uint) (percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (> threshold-days u0) (<= threshold-days u30)) err-invalid-surge-rate)
    (asserts! (and (>= percentage u50) (<= percentage u100)) err-invalid-surge-rate)
    (var-set discount-threshold threshold-days)
    (var-set discount-percentage percentage)
    (ok true)
  )
)

(define-read-only (get-outfit-demand-metrics (outfit-id uint))
  (map-get? outfit-demand-metrics { outfit-id: outfit-id })
)

(define-read-only (get-outfit-price-history (outfit-id uint) (timestamp uint))
  (map-get? outfit-price-history { outfit-id: outfit-id, timestamp: timestamp })
)

(define-read-only (get-weekly-rentals (outfit-id uint) (week-number uint))
  (default-to { rental-count: u0 }
    (map-get? weekly-rental-tracker { outfit-id: outfit-id, week-number: week-number }))
)

(define-read-only (get-surge-settings)
  {
    threshold: (var-get surge-threshold),
    multiplier: (var-get surge-multiplier)
  }
)

(define-read-only (get-discount-settings)
  {
    threshold-days: (var-get discount-threshold),
    percentage: (var-get discount-percentage)
  }
)

(define-read-only (calculate-dynamic-rental-cost (outfit-id uint) (duration-hours uint))
  (match (get-dynamic-price outfit-id)
    price-per-hour
      (let (
        (total-cost (* price-per-hour duration-hours))
        (platform-fee (/ (* total-cost (var-get platform-fee-percentage)) u100))
      )
        (some {
          price-per-hour: price-per-hour,
          total-cost: total-cost,
          platform-fee: platform-fee,
          owner-payment: (- total-cost platform-fee),
          pricing-tier: (match (map-get? outfit-demand-metrics { outfit-id: outfit-id })
            metrics (get price-tier metrics)
            u1
          )
        })
      )
    none
  )
)

(define-public (deposit-loyalty-tokens (amount uint))
  (let (
    (wallet (default-to { balance: u0, total-earned: u0, last-updated: u0 } 
                        (map-get? user-loyalty-wallet { user: tx-sender })))
  )
    (asserts! (> amount u0) err-invalid-deposit)
    (try! (stx-transfer? amount tx-sender contract-owner))
    (map-set user-loyalty-wallet
      { user: tx-sender }
      {
        balance: (+ (get balance wallet) amount),
        total-earned: (get total-earned wallet),
        last-updated: (var-get current-time)
      }
    )
    (ok true)
  )
)

(define-public (redeem-loyalty-rewards (amount uint))
  (let (
    (wallet (unwrap! (map-get? user-loyalty-wallet { user: tx-sender }) err-not-found))
  )
    (asserts! (> amount u0) err-invalid-deposit)
    (asserts! (>= (get balance wallet) amount) err-insufficient-balance)
    (try! (stx-transfer? amount contract-owner tx-sender))
    (map-set user-loyalty-wallet
      { user: tx-sender }
      {
        balance: (- (get balance wallet) amount),
        total-earned: (get total-earned wallet),
        last-updated: (var-get current-time)
      }
    )
    (ok true)
  )
)

(define-public (set-loyalty-reward-percentage (percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= percentage u20) err-invalid-surge-rate)
    (var-set loyalty-reward-percentage percentage)
    (ok true)
  )
)

(define-read-only (get-loyalty-wallet (user principal))
  (map-get? user-loyalty-wallet { user: user })
)

(define-read-only (get-user-rental-count (user principal))
  (default-to { count: u0 } (map-get? user-rental-count { user: user }))
)

(define-read-only (get-loyalty-reward-percentage)
  (var-get loyalty-reward-percentage)
)
