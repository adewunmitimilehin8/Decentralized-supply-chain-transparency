;; Product History Recorder Contract
;; Records supply chain events at each stage, verifies authenticity, tracks handling conditions, and enables consumer verification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-handler (err u104))
(define-constant err-invalid-product (err u105))
(define-constant err-invalid-stage (err u106))

;; Data Variables
(define-data-var product-nonce uint u0)
(define-data-var event-nonce uint u0)
(define-data-var handler-nonce uint u0)

;; Data Maps

;; Handler Registry
(define-map handlers
  { handler-id: uint }
  {
    handler-address: principal,
    organization-name: (string-ascii 100),
    certification: (string-ascii 100),
    verified: bool,
    active: bool,
    registered-at: uint
  }
)

(define-map handler-by-address
  { handler-address: principal }
  { handler-id: uint }
)

;; Product Registry
(define-map products
  { product-id: (string-ascii 50) }
  {
    origin-location: (string-ascii 100),
    product-type: (string-ascii 50),
    batch-number: (string-ascii 50),
    initial-handler: uint,
    current-handler: uint,
    registration-date: uint,
    metadata-uri: (string-ascii 256),
    is-authentic: bool,
    current-stage: (string-ascii 50)
  }
)

;; Supply Chain Events
(define-map supply-chain-events
  { event-id: uint }
  {
    product-id: (string-ascii 50),
    event-type: (string-ascii 50),
    handler-id: uint,
    location: (string-ascii 100),
    timestamp: uint,
    temperature: (optional int),
    humidity: (optional uint),
    notes: (string-ascii 200),
    previous-handler: uint
  }
)

;; Product Event Index
(define-map product-event-index
  { product-id: (string-ascii 50), index: uint }
  { event-id: uint }
)

(define-map product-event-count
  { product-id: (string-ascii 50) }
  { count: uint }
)

;; Handler Statistics
(define-map handler-stats
  { handler-id: uint }
  { products-handled: uint, events-recorded: uint }
)

;; Condition Alerts
(define-map condition-alerts
  { product-id: (string-ascii 50), alert-id: uint }
  {
    alert-type: (string-ascii 50),
    severity: (string-ascii 20),
    timestamp: uint,
    condition-value: int,
    threshold-exceeded: bool
  }
)

;; Certification Tracking
(define-map product-certifications
  { product-id: (string-ascii 50), certification-type: (string-ascii 50) }
  {
    issuer: principal,
    issue-date: uint,
    expiry-date: uint,
    certification-uri: (string-ascii 256),
    valid: bool
  }
)

;; Read-Only Functions

(define-read-only (get-product (product-id (string-ascii 50)))
  (map-get? products { product-id: product-id })
)

(define-read-only (get-handler (handler-id uint))
  (map-get? handlers { handler-id: handler-id })
)

(define-read-only (get-handler-by-address (handler-address principal))
  (map-get? handler-by-address { handler-address: handler-address })
)

(define-read-only (get-event (event-id uint))
  (map-get? supply-chain-events { event-id: event-id })
)

(define-read-only (get-product-event-count (product-id (string-ascii 50)))
  (default-to u0
    (get count (map-get? product-event-count { product-id: product-id }))
  )
)

(define-read-only (get-product-event-by-index (product-id (string-ascii 50)) (index uint))
  (map-get? product-event-index { product-id: product-id, index: index })
)

(define-read-only (get-handler-stats (handler-id uint))
  (map-get? handler-stats { handler-id: handler-id })
)

(define-read-only (verify-product-authenticity (product-id (string-ascii 50)))
  (match (get-product product-id)
    product (ok (get is-authentic product))
    (err err-not-found)
  )
)

(define-read-only (get-product-certification 
  (product-id (string-ascii 50)) 
  (certification-type (string-ascii 50)))
  (map-get? product-certifications 
    { product-id: product-id, certification-type: certification-type })
)

;; Public Functions

;; Register Handler
(define-public (register-handler
  (organization-name (string-ascii 100))
  (certification (string-ascii 100)))
  (let
    (
      (new-id (+ (var-get handler-nonce) u1))
    )
    (asserts! (is-none (get-handler-by-address tx-sender)) err-already-exists)
    
    (map-set handlers
      { handler-id: new-id }
      {
        handler-address: tx-sender,
        organization-name: organization-name,
        certification: certification,
        verified: false,
        active: true,
        registered-at: block-height
      }
    )
    
    (map-set handler-by-address
      { handler-address: tx-sender }
      { handler-id: new-id }
    )
    
    (map-set handler-stats
      { handler-id: new-id }
      { products-handled: u0, events-recorded: u0 }
    )
    
    (var-set handler-nonce new-id)
    (ok new-id)
  )
)

;; Verify Handler
(define-public (verify-handler (handler-id uint))
  (let
    (
      (handler (unwrap! (get-handler handler-id) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set handlers
      { handler-id: handler-id }
      (merge handler { verified: true })
    )
    (ok true)
  )
)

;; Register Product
(define-public (register-product
  (product-id (string-ascii 50))
  (origin-location (string-ascii 100))
  (product-type (string-ascii 50))
  (batch-number (string-ascii 50))
  (metadata-uri (string-ascii 256)))
  (let
    (
      (handler-data (unwrap! (get-handler-by-address tx-sender) err-invalid-handler))
      (handler-id (get handler-id handler-data))
      (handler (unwrap! (get-handler handler-id) err-invalid-handler))
    )
    (asserts! (is-none (get-product product-id)) err-already-exists)
    (asserts! (get verified handler) err-unauthorized)
    (asserts! (get active handler) err-unauthorized)
    
    (map-set products
      { product-id: product-id }
      {
        origin-location: origin-location,
        product-type: product-type,
        batch-number: batch-number,
        initial-handler: handler-id,
        current-handler: handler-id,
        registration-date: block-height,
        metadata-uri: metadata-uri,
        is-authentic: true,
        current-stage: "registered"
      }
    )
    
    (map-set product-event-count
      { product-id: product-id }
      { count: u0 }
    )
    
    ;; Update handler stats
    (let
      (
        (stats (unwrap! (get-handler-stats handler-id) err-not-found))
      )
      (map-set handler-stats
        { handler-id: handler-id }
        {
          products-handled: (+ (get products-handled stats) u1),
          events-recorded: (get events-recorded stats)
        }
      )
    )
    
    (ok true)
  )
)

;; Record Supply Chain Event
(define-public (record-event
  (product-id (string-ascii 50))
  (event-type (string-ascii 50))
  (location (string-ascii 100))
  (temperature (optional int))
  (humidity (optional uint))
  (notes (string-ascii 200)))
  (let
    (
      (new-event-id (+ (var-get event-nonce) u1))
      (handler-data (unwrap! (get-handler-by-address tx-sender) err-invalid-handler))
      (handler-id (get handler-id handler-data))
      (handler (unwrap! (get-handler handler-id) err-invalid-handler))
      (product (unwrap! (get-product product-id) err-invalid-product))
      (event-count (get-product-event-count product-id))
      (current-handler (get current-handler product))
    )
    (asserts! (get verified handler) err-unauthorized)
    (asserts! (get active handler) err-unauthorized)
    (asserts! (get is-authentic product) err-invalid-product)
    
    ;; Record event
    (map-set supply-chain-events
      { event-id: new-event-id }
      {
        product-id: product-id,
        event-type: event-type,
        handler-id: handler-id,
        location: location,
        timestamp: block-height,
        temperature: temperature,
        humidity: humidity,
        notes: notes,
        previous-handler: current-handler
      }
    )
    
    ;; Update product event index
    (map-set product-event-index
      { product-id: product-id, index: event-count }
      { event-id: new-event-id }
    )
    
    (map-set product-event-count
      { product-id: product-id }
      { count: (+ event-count u1) }
    )
    
    ;; Update product current handler and stage
    (map-set products
      { product-id: product-id }
      (merge product {
        current-handler: handler-id,
        current-stage: event-type
      })
    )
    
    ;; Update handler stats
    (let
      (
        (stats (unwrap! (get-handler-stats handler-id) err-not-found))
      )
      (map-set handler-stats
        { handler-id: handler-id }
        {
          products-handled: (get products-handled stats),
          events-recorded: (+ (get events-recorded stats) u1)
        }
      )
    )
    
    (var-set event-nonce new-event-id)
    (ok new-event-id)
  )
)

;; Add Product Certification
(define-public (add-certification
  (product-id (string-ascii 50))
  (certification-type (string-ascii 50))
  (issue-date uint)
  (expiry-date uint)
  (certification-uri (string-ascii 256)))
  (let
    (
      (product (unwrap! (get-product product-id) err-invalid-product))
      (handler-data (unwrap! (get-handler-by-address tx-sender) err-invalid-handler))
      (handler-id (get handler-id handler-data))
      (handler (unwrap! (get-handler handler-id) err-invalid-handler))
    )
    (asserts! (get verified handler) err-unauthorized)
    (asserts! (is-eq (get current-handler product) handler-id) err-unauthorized)
    
    (map-set product-certifications
      { product-id: product-id, certification-type: certification-type }
      {
        issuer: tx-sender,
        issue-date: issue-date,
        expiry-date: expiry-date,
        certification-uri: certification-uri,
        valid: true
      }
    )
    (ok true)
  )
)

;; Revoke Product Authenticity
(define-public (revoke-authenticity (product-id (string-ascii 50)))
  (let
    (
      (product (unwrap! (get-product product-id) err-invalid-product))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set products
      { product-id: product-id }
      (merge product { is-authentic: false })
    )
    (ok true)
  )
)

;; Update Handler Status
(define-public (update-handler-status (handler-id uint) (active bool))
  (let
    (
      (handler (unwrap! (get-handler handler-id) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set handlers
      { handler-id: handler-id }
      (merge handler { active: active })
    )
    (ok true)
  )
)


;; title: product-history-recorder
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

