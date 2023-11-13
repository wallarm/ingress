/*
Copyright 2017 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package flags

import (
	"os"
	"testing"
)

func TestNoMandatoryFlag(t *testing.T) {
	_, _, err := ParseFlags()
	if err != nil {
		t.Fatalf("Expected no error but got: %s", err)
	}
}

func TestDefaults(t *testing.T) {
	ResetForTesting(func() { t.Fatal("Parsing failed") })

	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()
	os.Args = []string{
		"cmd",
		"--default-backend-service", "namespace/test",
		"--http-port", "0",
		"--https-port", "0",
	}

	showVersion, conf, err := ParseFlags()
	if err != nil {
		t.Fatalf("Unexpected error parsing default flags: %v", err)
	}

	if showVersion {
		t.Fatal("Expected flag \"show-version\" to be false")
	}

	if conf == nil {
		t.Fatal("Expected a controller Configuration")
	}
}

func TestSetupSSLProxy(_ *testing.T) {
	// TODO TestSetupSSLProxy
}

func TestFlagConflict(t *testing.T) {
	ResetForTesting(func() { t.Fatal("Parsing failed") })

	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()
	os.Args = []string{"cmd", "--publish-service", "namespace/test", "--http-port", "0", "--https-port", "0", "--publish-status-address", "1.1.1.1"}

	_, _, err := ParseFlags()
	if err == nil {
		t.Fatalf("Expected an error parsing flags but none returned")
	}
}

func TestMaxmindEdition(t *testing.T) {
	ResetForTesting(func() { t.Fatal("Parsing failed") })

	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()
	os.Args = []string{"cmd", "--publish-service", "namespace/test", "--http-port", "0", "--https-port", "0", "--maxmind-license-key", "0000000", "--maxmind-edition-ids", "GeoLite2-City, TestCheck"}

	_, _, err := ParseFlags()
	if err == nil {
		t.Fatalf("Expected an error parsing flags but none returned")
	}
}

func TestMaxmindMirror(t *testing.T) {
	ResetForTesting(func() { t.Fatal("Parsing failed") })

	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()
	os.Args = []string{"cmd", "--publish-service", "namespace/test", "--http-port", "0", "--https-port", "0", "--maxmind-mirror", "http://geoip.local", "--maxmind-license-key", "0000000", "--maxmind-edition-ids", "GeoLite2-City, TestCheck"}

	_, _, err := ParseFlags()
	if err == nil {
		t.Fatalf("Expected an error parsing flags but none returned")
	}
}

func TestMaxmindRetryDownload(t *testing.T) {
	ResetForTesting(func() { t.Fatal("Parsing failed") })

	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()
	os.Args = []string{"cmd", "--publish-service", "namespace/test", "--http-port", "0", "--https-port", "0", "--maxmind-mirror", "http://127.0.0.1", "--maxmind-license-key", "0000000", "--maxmind-edition-ids", "GeoLite2-City", "--maxmind-retries-timeout", "1s", "--maxmind-retries-count", "3"}

	_, _, err := ParseFlags()
	if err == nil {
		t.Fatalf("Expected an error parsing flags but none returned")
	}
}
