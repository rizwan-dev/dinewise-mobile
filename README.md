# Dinewise mobile

The Flutter app for **Dinewise**, restaurant ordering for a single restaurant. The demo
restaurant is **Tadka Lane**, a North Indian kitchen in Baner, Pune.

One app, two modes:

- **Customer mode**: browse a photo-led menu, build a cart with sizes and add-ons, sign in with a
  one-time code, order for delivery or pickup (cash), and follow the order live.
- **Kitchen mode**: staff sign in and run a live kitchen board (New, Cooking, Ready, Out), move
  orders on with one big button, reject with a reason, and mark dishes sold out.

It talks only to the Dinewise JSON API (`/api/v1`) of the
[web app](https://github.com/rizwan-dev/dinewise), live at
[dinewise.riztechacademy.com](https://dinewise.riztechacademy.com). The API contract is
[`docs/api.md`](https://github.com/rizwan-dev/dinewise/blob/main/docs/api.md) in that repository.

## Run it

Flutter 3.47 (Dart 3.13).

```sh
flutter pub get

# Against the public demo (the default base URL)
flutter run

# Against the API running locally (`docker compose up` in the web repo, port 8082)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8082/api/v1   # Android emulator
flutter run --dart-define=API_BASE_URL=http://localhost:8082/api/v1  # iOS simulator
```

On the demo, the sign-in screen offers **Fill it in** with the one-time code (no SMS is sent),
and kitchen mode offers **Try as kitchen** / **Try as manager**. Both appear only when the API's
`GET /restaurant` says `demo: true`. Coupons to try: `WELCOME50` (first order) and `TADKA10`.
Delivery pincodes: 411045, 411021, 411007, 411008.

Plain HTTP is allowed only where the local stack needs it: the Android network-security config
that permits it is in the **debug** source set only, and iOS has an App Transport Security
exception for `localhost` alone. Release builds talk HTTPS.

## Tests

```sh
flutter analyze                                   # zero issues, strict lints
dart format --set-exit-if-changed lib test integration_test
flutter test                                      # unit + widget tests
flutter test integration_test \
  --dart-define=API_BASE_URL=http://10.0.2.2:8082/api/v1   # the happy path on a device
```

- **Unit tests** cover money formatting (Indian digit grouping, paise), times in Asia/Kolkata,
  the SSE parser (the contract's own sample stream, CRLF, split chunks, comments, `retry`),
  reconnect and back-off, API error mapping, the cart (merging, limits, coupons, quote requests),
  the dish sheet's choice rules and the checkout request body.
- **Widget tests** run the whole app against `FakeApi`, an in-memory `/api/v1` that serves the
  recorded demo menu and follows the contract (quotes with the real charges, one-time codes,
  orders, the kitchen board and both event streams). They cover browsing and filtering, the dish
  sheet, the cart and bill, coupon errors, quote problems, slots, sign-in, checkout, a full slot,
  live order tracking (including a dropped stream), cancel, the kitchen board on phone and tablet,
  every move, reject, a stale move, sold out, staff sign-out, and a `401` dropping the session.
- **The integration test** (`integration_test/app_flow_test.dart`) drives the real app against a
  running API: menu, cart, sign in with the demo code, a cash order, the kitchen starting it
  (the customer's screen changes without a refresh), and kitchen mode marking it ready.

CI (GitHub Actions) runs format, analyze (infos fail the build), the tests with coverage, and an
Android debug build.

## How it is built

```
lib/
  core/
    api/        ApiClient (transport, bearer tokens), ApiException (the one error type)
    live/       SSE parser, LiveStream (reconnect + back-off), followLive() for providers
    auth/       Sessions (customer and staff, kept apart), secure token storage
    format/     Money (paise) and time (Asia/Kolkata) formatting
    theme/      Brand colours, Material 3 theme, Inter + Fraunces
    router/     go_router routes, guards, the customer shell
    widgets/    Veg mark, photos, skeletons, error/empty states, steppers
  features/
    home/ restaurant/ menu/ cart/ checkout/ account/ orders/ kitchen/
      data/     models, repositories, Riverpod providers
      ui/       screens and widgets
```

Decisions worth knowing:

- **Riverpod 3 for state, go_router for navigation.** Providers own server state; widgets stay
  thin. The router re-runs its guards whenever a session changes, so a `401` anywhere sends the
  user back to sign-in, and kitchen routes stay closed without a staff session.
- **Hand-written immutable models, not freezed/json_serializable.** The contract is small and
  stable (fields may be added, never renamed) and models only need `fromJson`. Hand-written
  parsing keeps the build free of a code-generation step and lets each model pick sensible
  defaults for fields a future server may add. Value equality is needed in one place (quote
  requests), which compares a canonical JSON encoding.
- **One error type.** Every non-2xx answer becomes an `ApiException` with the server's stable
  `code`, its user-facing `message` (shown as it is) and the `field` at fault, which forms show
  next to the right input. Failures that never reached the server become a friendly `NETWORK`
  error. A `401 UNAUTHENTICATED` on an authenticated call drops that kind of session.
- **The server decides every price.** The cart re-quotes (debounced) whenever lines, fulfilment,
  pincode, coupon or the signed-in customer change, and the bill shows `POST /quote`'s totals and
  problems exactly. The app's own sum only labels the Add button and the cart bar.
- **Live updates without EventSource.** `SseParser` reads a streamed `http` response line by line.
  `LiveStream` reconnects after the server's `retry` (3 s) when a stream ends (the server ends
  them after about 4.5 minutes), backs off up to 30 s while the network is down, stops on
  `401`/`404`, and reports every (re)connect so the screen fetches again, because events are not
  replayed. Streams close when the app goes to the background and reopen, with a fresh fetch,
  when it comes back. An order's stream stops once the order is final.
- **Money is integer paise**, formatted the `en-IN` way (₹1,23,456, and ₹280 rather than ₹280.00).
  **Times are shown in Asia/Kolkata** whatever the phone's zone is. India has one fixed offset
  and no daylight saving, so a constant +05:30 is exact without shipping the time-zone database.
- **Tokens** live in the Keychain / Android Keystore (flutter_secure_storage). The customer and
  staff sessions are separate: one phone can hold both, and signing out of one keeps the other.
- **Fonts are bundled**, never fetched: Inter and Fraunces, both under the SIL Open Font License
  (licences in `assets/fonts/`), cut into static weights and subset to Latin plus ₹.
- **Accessibility**: semantics labels on marks, steppers, tickets and live regions; 48 dp touch
  targets; text scaling respected (capped at 160% where layouts would break); reduced motion
  turns off the skeleton shimmer.

## Notes on the API

Things found while building against the v1 contract:

- There is no endpoint to set the customer's name on its own. It can only be sent with the code
  (`/auth/otp/verify`) or with an order. A new customer is asked for their name after signing in;
  the app keeps it with the session and sends it with the first order.
- `POST /quote` with `DELIVERY` and no pincode answers `NO_DELIVERY` ("We do not deliver to that
  pincode yet"), the same as an unserved pincode. The app does not quote delivery until a pincode
  is entered and asks for one instead.
- The server closes idle keep-alive connections after a few seconds, which can surface as
  "Connection closed before full header was received" on the next request over a reused
  connection. The client retries once in exactly that case (the server never saw the request).

## Licence

MIT. Fonts: SIL Open Font License 1.1 (see `assets/fonts/`).
