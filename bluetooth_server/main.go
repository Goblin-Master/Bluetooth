package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type bleMessage struct {
	ID         int       `json:"id"`
	DeviceID   string    `json:"device_id"`
	DeviceName string    `json:"device_name"`
	Payload    string    `json:"payload"`
	ReceivedAt time.Time `json:"received_at"`
}

type messageStore struct {
	mu       sync.Mutex
	nextID   int
	messages []bleMessage
}

func newServer() http.Handler {
	store := &messageStore{nextID: 1}
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		if handlePreflight(w, r) {
			return
		}
		if r.Method != http.MethodGet {
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/ble/messages", func(w http.ResponseWriter, r *http.Request) {
		if handlePreflight(w, r) {
			return
		}

		switch r.Method {
		case http.MethodGet:
			writeJSON(w, http.StatusOK, store.list())
		case http.MethodPost:
			message, err := decodeBLEMessage(r)
			if err != nil {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
			created := store.add(message)
			log.Printf("ble message: device_id=%q device_name=%q payload=%q", created.DeviceID, created.DeviceName, created.Payload)
			writeJSON(w, http.StatusCreated, created)
		default:
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		}
	})

	return withCORS(mux)
}

func main() {
	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = ":8080"
	}

	log.Printf("BLE bridge backend listening on %s", addr)
	log.Print("Flow: Flutter BLE client -> Windows GATT server bridge -> POST /ble/messages")
	if err := http.ListenAndServe(addr, newServer()); err != nil {
		log.Fatal(err)
	}
}

func decodeBLEMessage(r *http.Request) (bleMessage, error) {
	defer r.Body.Close()

	var message bleMessage
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&message); err != nil {
		return bleMessage{}, errors.New("invalid JSON body")
	}

	message.DeviceID = strings.TrimSpace(message.DeviceID)
	message.DeviceName = strings.TrimSpace(message.DeviceName)
	message.Payload = strings.TrimSpace(message.Payload)
	if message.Payload == "" {
		return bleMessage{}, errors.New("payload is required")
	}

	return message, nil
}

func (s *messageStore) add(message bleMessage) bleMessage {
	s.mu.Lock()
	defer s.mu.Unlock()

	message.ID = s.nextID
	message.ReceivedAt = time.Now().UTC()
	s.nextID++
	s.messages = append(s.messages, message)
	return message
}

func (s *messageStore) list() []bleMessage {
	s.mu.Lock()
	defer s.mu.Unlock()

	messages := make([]bleMessage, len(s.messages))
	copy(messages, s.messages)
	return messages
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		next.ServeHTTP(w, r)
	})
}

func handlePreflight(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodOptions {
		return false
	}
	w.WriteHeader(http.StatusNoContent)
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
