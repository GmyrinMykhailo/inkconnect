package journal

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestHashJournalEventDeterministic(t *testing.T) {
	payload := sampleCanonicalJournalEventPayload()

	first, err := hashJournalEvent(payload)
	if err != nil {
		t.Fatalf("hashJournalEvent() first call error = %v", err)
	}
	second, err := hashJournalEvent(payload)
	if err != nil {
		t.Fatalf("hashJournalEvent() second call error = %v", err)
	}

	if first != second {
		t.Fatalf("hashJournalEvent() is not deterministic: first=%s second=%s", first, second)
	}
	if len(first) != 64 {
		t.Fatalf("hashJournalEvent() returned hash with length %d, want 64", len(first))
	}
}

func TestHashJournalEventNormalizesJSONAndTime(t *testing.T) {
	msk := time.FixedZone("MSK", 3*60*60)
	createdAt := time.Date(2026, 5, 12, 18, 30, 45, 123456789, msk)

	left := sampleCanonicalJournalEventPayload()
	left.PayloadJSON = json.RawMessage(`{"z":[3,2,1],"a":{"b":true}}`)
	left.CreatedAt = createdAt

	right := sampleCanonicalJournalEventPayload()
	right.PayloadJSON = json.RawMessage(`{ "a" : { "b" : true }, "z" : [3, 2, 1] }`)
	right.CreatedAt = createdAt.UTC()

	leftHash, err := hashJournalEvent(left)
	if err != nil {
		t.Fatalf("hashJournalEvent(left) error = %v", err)
	}
	rightHash, err := hashJournalEvent(right)
	if err != nil {
		t.Fatalf("hashJournalEvent(right) error = %v", err)
	}

	if leftHash != rightHash {
		t.Fatalf("hashJournalEvent() did not normalize JSON/time: left=%s right=%s", leftHash, rightHash)
	}
}

func TestHashJournalEventChangesWhenPayloadChanges(t *testing.T) {
	left := sampleCanonicalJournalEventPayload()
	left.PayloadJSON = json.RawMessage(`{"completed":true}`)

	right := sampleCanonicalJournalEventPayload()
	right.PayloadJSON = json.RawMessage(`{"completed":false}`)

	assertDifferentJournalHashes(t, left, right)
}

func TestHashJournalEventChangesWhenPreviousHashChanges(t *testing.T) {
	left := sampleCanonicalJournalEventPayload()
	left.PreviousHash = stringPointer(strings.Repeat("a", 64))

	right := sampleCanonicalJournalEventPayload()
	right.PreviousHash = stringPointer(strings.Repeat("b", 64))

	assertDifferentJournalHashes(t, left, right)
}

func TestHashJournalEventRejectsInvalidJSON(t *testing.T) {
	payload := sampleCanonicalJournalEventPayload()
	payload.PayloadJSON = json.RawMessage(`{"broken":`)

	if _, err := hashJournalEvent(payload); err == nil {
		t.Fatalf("hashJournalEvent() accepted invalid JSON")
	}
}

func TestVerifyEd25519SignatureAcceptsValidSignature(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("GenerateKey() error = %v", err)
	}

	eventHash := strings.Repeat("a", 64)
	signature := ed25519.Sign(privateKey, []byte(eventHash))

	err = verifyEd25519Signature(
		base64.StdEncoding.EncodeToString(publicKey),
		eventHash,
		base64.StdEncoding.EncodeToString(signature),
	)
	if err != nil {
		t.Fatalf("verifyEd25519Signature() error = %v", err)
	}
}

func TestVerifyEd25519SignatureRejectsTamperedHash(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("GenerateKey() error = %v", err)
	}

	signature := ed25519.Sign(privateKey, []byte(strings.Repeat("a", 64)))
	err = verifyEd25519Signature(
		base64.StdEncoding.EncodeToString(publicKey),
		strings.Repeat("b", 64),
		base64.StdEncoding.EncodeToString(signature),
	)
	if !errors.Is(err, ErrInvalidSignature) {
		t.Fatalf("verifyEd25519Signature() error = %v, want %v", err, ErrInvalidSignature)
	}
}

func TestVerifyEd25519SignatureRejectsInvalidSignature(t *testing.T) {
	publicKey, _, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatalf("GenerateKey() error = %v", err)
	}
	encodedPublicKey := base64.StdEncoding.EncodeToString(publicKey)

	tests := []struct {
		name      string
		signature string
	}{
		{name: "not base64", signature: "not-base64"},
		{name: "wrong length", signature: base64.StdEncoding.EncodeToString([]byte("short"))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := verifyEd25519Signature(encodedPublicKey, strings.Repeat("a", 64), tt.signature)
			if !errors.Is(err, ErrInvalidSignature) {
				t.Fatalf("verifyEd25519Signature() error = %v, want %v", err, ErrInvalidSignature)
			}
		})
	}
}

func TestVerifyEd25519SignatureRejectsInvalidPublicKey(t *testing.T) {
	tests := []struct {
		name      string
		publicKey string
	}{
		{name: "not base64", publicKey: "not-base64"},
		{name: "wrong length", publicKey: base64.StdEncoding.EncodeToString([]byte("short"))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := verifyEd25519Signature(tt.publicKey, strings.Repeat("a", 64), "not-used")
			if !errors.Is(err, ErrInvalidSignature) {
				t.Fatalf("verifyEd25519Signature() error = %v, want %v", err, ErrInvalidSignature)
			}
		})
	}
}

func TestIntegrityReportAddIssueSetsFirstInvalidEventOnce(t *testing.T) {
	var report IntegrityReport

	report.addIntegrityIssue("event-1", "first issue")
	report.addIntegrityIssue("event-2", "second issue")

	if report.FirstInvalidEventID == nil {
		t.Fatalf("FirstInvalidEventID is nil")
	}
	if *report.FirstInvalidEventID != "event-1" {
		t.Fatalf("FirstInvalidEventID = %q, want event-1", *report.FirstInvalidEventID)
	}
	if got, want := len(report.Issues), 2; got != want {
		t.Fatalf("len(Issues) = %d, want %d", got, want)
	}
}

func TestIntegrityReportAddIssueWithoutEventDoesNotSetFirstInvalidEvent(t *testing.T) {
	var report IntegrityReport

	report.addIntegrityIssue("", "journal final hash mismatch")

	if report.FirstInvalidEventID != nil {
		t.Fatalf("FirstInvalidEventID = %q, want nil", *report.FirstInvalidEventID)
	}
	if got, want := len(report.Issues), 1; got != want {
		t.Fatalf("len(Issues) = %d, want %d", got, want)
	}
}

func TestConfirmationHashDependsOnPayloadAndPreviousHash(t *testing.T) {
	base := confirmationHash([]byte(`{"step":1}`), strings.Repeat("a", 64))
	same := confirmationHash([]byte(`{"step":1}`), strings.Repeat("a", 64))
	changedPayload := confirmationHash([]byte(`{"step":2}`), strings.Repeat("a", 64))
	changedPreviousHash := confirmationHash([]byte(`{"step":1}`), strings.Repeat("b", 64))

	if base != same {
		t.Fatalf("confirmationHash() is not deterministic: base=%s same=%s", base, same)
	}
	if base == changedPayload {
		t.Fatalf("confirmationHash() did not change after payload change")
	}
	if base == changedPreviousHash {
		t.Fatalf("confirmationHash() did not change after previous hash change")
	}
}

func sampleCanonicalJournalEventPayload() canonicalJournalEventPayload {
	return canonicalJournalEventPayload{
		EventType:   JournalEventTypeStepCompletedByClient,
		JournalID:   "journal-1",
		StepID:      "step-1",
		ActorID:     "client-1",
		ActorRole:   JournalActorRoleClient,
		PayloadJSON: json.RawMessage(`{"completed":true,"step":1}`),
		CreatedAt:   time.Date(2026, 5, 12, 15, 30, 45, 123456789, time.UTC),
	}
}

func assertDifferentJournalHashes(t *testing.T, left canonicalJournalEventPayload, right canonicalJournalEventPayload) {
	t.Helper()

	leftHash, err := hashJournalEvent(left)
	if err != nil {
		t.Fatalf("hashJournalEvent(left) error = %v", err)
	}
	rightHash, err := hashJournalEvent(right)
	if err != nil {
		t.Fatalf("hashJournalEvent(right) error = %v", err)
	}
	if leftHash == rightHash {
		t.Fatalf("hashJournalEvent() returned equal hashes: %s", leftHash)
	}
}

func stringPointer(value string) *string {
	return &value
}
