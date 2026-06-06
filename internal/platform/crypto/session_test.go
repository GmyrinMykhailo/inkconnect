package crypto

import (
	"encoding/hex"
	"testing"
)

func TestGenerateSessionTokenReturnsTokenAndMatchingHash(t *testing.T) {
	token, hash, err := GenerateSessionToken()
	if err != nil {
		t.Fatalf("GenerateSessionToken returned error: %v", err)
	}
	if token == "" {
		t.Fatal("token should not be empty")
	}
	if hash == "" {
		t.Fatal("hash should not be empty")
	}
	if got := GenerateTokenHash(token); got != hash {
		t.Fatalf("GenerateTokenHash(token) = %q, want %q", got, hash)
	}
	if len(hash) != 64 {
		t.Fatalf("hash length = %d, want 64", len(hash))
	}
	if _, err := hex.DecodeString(hash); err != nil {
		t.Fatalf("hash should be hex encoded: %v", err)
	}
}

func TestGenerateSessionTokenProducesDifferentTokens(t *testing.T) {
	firstToken, firstHash, err := GenerateSessionToken()
	if err != nil {
		t.Fatalf("first GenerateSessionToken returned error: %v", err)
	}
	secondToken, secondHash, err := GenerateSessionToken()
	if err != nil {
		t.Fatalf("second GenerateSessionToken returned error: %v", err)
	}
	if firstToken == secondToken {
		t.Fatal("two generated tokens should differ")
	}
	if firstHash == secondHash {
		t.Fatal("two generated token hashes should differ")
	}
}

func TestGenerateTokenHashDeterministic(t *testing.T) {
	first := GenerateTokenHash("session-token")
	second := GenerateTokenHash("session-token")
	other := GenerateTokenHash("other-session-token")

	if first != second {
		t.Fatalf("same token hashes differ: %q vs %q", first, second)
	}
	if first == other {
		t.Fatal("different tokens should have different hashes")
	}
}
