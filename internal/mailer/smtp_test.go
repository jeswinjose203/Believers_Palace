package mailer

import (
	"context"
	"net"
	"testing"
	"time"
)

func TestSMTPExitsWhenRequestIsCanceled(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	host, port, err := net.SplitHostPort(listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	mailer := NewSMTPMailer(SMTPConfig{Host: host, Port: port, From: "sender@example.test"})
	result := make(chan error, 1)
	go func() {
		result <- mailer.SendEmailVerification(ctx, "recipient@example.test", "123456")
	}()
	_ = listener.(*net.TCPListener).SetDeadline(time.Now().Add(2 * time.Second))
	conn, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	// Leave the client waiting for the greeting.
	cancel()
	select {
	case err := <-result:
		if err == nil {
			t.Fatal("a canceled SMTP exchange succeeded")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("SMTP exchange remained blocked after cancellation")
	}
}
