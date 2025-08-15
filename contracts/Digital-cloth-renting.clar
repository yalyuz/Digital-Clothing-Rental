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

(define-data-var next-outfit-id uint u1)
(define-data-var next-rental-id uint u1)
(define-data-var next-review-id uint u1)
(define-data-var platform-fee-percentage uint u5)
(define-data-var current-time uint u0)

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
    (total-cost (* (get rental-price-per-hour outfit) duration-hours))
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

(define-private (remove-rental-id (id uint))
  (not (is-eq id (var-get next-rental-id)))
)
