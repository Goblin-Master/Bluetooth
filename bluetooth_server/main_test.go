package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthReturnsOK(t *testing.T) {
	server := newServer()
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder := httptest.NewRecorder()

	server.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(recorder.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("expected status ok, got %q", body["status"])
	}
}

func TestMessagesStartEmpty(t *testing.T) {
	server := newServer()
	request := httptest.NewRequest(http.MethodGet, "/ble/messages", nil)
	recorder := httptest.NewRecorder()

	server.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var messages []bleMessage
	if err := json.NewDecoder(recorder.Body).Decode(&messages); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(messages) != 0 {
		t.Fatalf("expected no messages, got %d", len(messages))
	}
}

func TestPostMessageStoresMessage(t *testing.T) {
	server := newServer()
	payload := []byte(`{"device_id":"pc-ble","device_name":"Windows Bridge","payload":"hello"}`)
	post := httptest.NewRequest(http.MethodPost, "/ble/messages", bytes.NewReader(payload))
	post.Header.Set("Content-Type", "application/json")
	postRecorder := httptest.NewRecorder()

	server.ServeHTTP(postRecorder, post)

	if postRecorder.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, postRecorder.Code)
	}

	var created bleMessage
	if err := json.NewDecoder(postRecorder.Body).Decode(&created); err != nil {
		t.Fatalf("decode created message: %v", err)
	}
	if created.ID != 1 {
		t.Fatalf("expected id 1, got %d", created.ID)
	}
	if created.DeviceID != "pc-ble" || created.DeviceName != "Windows Bridge" || created.Payload != "hello" {
		t.Fatalf("unexpected message: %#v", created)
	}
	if created.ReceivedAt.IsZero() {
		t.Fatal("expected received_at to be set")
	}

	get := httptest.NewRequest(http.MethodGet, "/ble/messages", nil)
	getRecorder := httptest.NewRecorder()
	server.ServeHTTP(getRecorder, get)

	var messages []bleMessage
	if err := json.NewDecoder(getRecorder.Body).Decode(&messages); err != nil {
		t.Fatalf("decode messages: %v", err)
	}
	if len(messages) != 1 {
		t.Fatalf("expected one message, got %d", len(messages))
	}
	if messages[0].Payload != "hello" {
		t.Fatalf("expected stored payload hello, got %q", messages[0].Payload)
	}
}

func TestPostMessageRejectsEmptyPayload(t *testing.T) {
	server := newServer()
	request := httptest.NewRequest(http.MethodPost, "/ble/messages", bytes.NewReader([]byte(`{"device_id":"pc-ble","payload":""}`)))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	server.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, recorder.Code)
	}
}

func TestOptionsAllowsCorsPreflight(t *testing.T) {
	server := newServer()
	request := httptest.NewRequest(http.MethodOptions, "/ble/messages", nil)
	recorder := httptest.NewRecorder()

	server.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusNoContent {
		t.Fatalf("expected status %d, got %d", http.StatusNoContent, recorder.Code)
	}
	if recorder.Header().Get("Access-Control-Allow-Origin") != "*" {
		t.Fatalf("expected CORS header, got %q", recorder.Header().Get("Access-Control-Allow-Origin"))
	}
}
