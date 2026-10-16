// Copyright 2026 The Ebitengine Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Derived from ebiten v2.10.5 skills/run-ebitengine-app-headless/_driver/main.go and modified for the
// av-marketplace qa plugin: JSON-scripted steps, named frame shots, result.json and a single guest reaper.
// The Apache License 2.0 text is in LICENSE next to this file.

// This is the QA engine's headless host for Ebitengine apps. It runs a guest binary built with
// -tags ebitenginevmguest from a hidden, unfocused host window, executes the steps of a JSON script
// (ticks, keys, text, mouse input and frame shots) and writes result.json, the shots and the guest's
// output into the -out directory. The QA engine builds it through `go build -overlay` inside the
// project's module, so host and guest always share the project's Ebitengine version.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/png"
	"io"
	"math"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/exp/vmhost"
)

const (
	maxSteps           = 500
	maxTotalTicks      = 36000
	maxWaitTicks       = 36000
	maxKeyTicks        = 600
	defaultKeyTicks    = 2
	maxTypeRunes       = 200
	maxShots           = 50
	maxScroll          = 100
	maxDetail          = 300
	guestExitTimeout   = 10 * time.Second
	handshakeExitGrace = 2 * time.Second
)

var (
	guestPath     = flag.String("guest", "", "guest binary built with -tags ebitenginevmguest (required)")
	scriptPath    = flag.String("script", "", "steps JSON file (required)")
	outDir        = flag.String("out", "", "existing directory for result.json, shots and guest.raw.log (required)")
	logicalW      = flag.Int("w", 960, "logical screen width in device-independent pixels")
	logicalH      = flag.Int("h", 540, "logical screen height in device-independent pixels")
	acceptTimeout = flag.Duration("accept-timeout", 30*time.Second, "how long the guest may take to connect")
	idleTimeout   = flag.Duration("idle-timeout", 30*time.Second, "how long the guest may make no progress")
	deadline      = flag.Duration("deadline", 0, "wall-clock bound of the whole host run; 0 means none")
)

var shotName = regexp.MustCompile(`^[A-Za-z0-9_-]{1,40}$`)

type stepKind int

const (
	stepWait stepKind = iota
	stepKey
	stepHold
	stepRelease
	stepType
	stepMove
	stepClick
	stepScroll
	stepShot
)

// step is one validated script step.
type step struct {
	kind   stepKind
	ticks  int
	key    ebiten.Key
	text   string
	x, y   float64
	button ebiten.MouseButton
	name   string
}

// actions maps every action key of the script format to its kind. type_env is part of the format but
// must be resolved by the QA engine before the host runs, so it maps to -1.
var actions = map[string]stepKind{
	"wait":     stepWait,
	"key":      stepKey,
	"hold":     stepHold,
	"release":  stepRelease,
	"type":     stepType,
	"type_env": -1,
	"move":     stepMove,
	"click":    stepClick,
	"scroll":   stepScroll,
	"shot":     stepShot,
}

var buttons = map[string]ebiten.MouseButton{
	"left":   ebiten.MouseButtonLeft,
	"right":  ebiten.MouseButtonRight,
	"middle": ebiten.MouseButtonMiddle,
}

type shotRecord struct {
	Name string `json:"name"`
	File string `json:"file"`
	Tick int    `json:"tick"`
}

type result struct {
	Result   string       `json:"result"`
	Detail   *string      `json:"detail"`
	Step     *int         `json:"step"`
	ExitCode *int         `json:"exit_code"`
	Ticks    int          `json:"ticks"`
	TPS      int          `json:"tps"`
	Scale    *float64     `json:"scale"`
	Screen   [2]int       `json:"screen"`
	Shots    []shotRecord `json:"shots"`
}

func (r *result) set(kind string, step *int, detail string) {
	r.Result = kind
	r.Step = step
	line := detail
	if i := strings.IndexAny(line, "\r\n"); i >= 0 {
		line = line[:i]
	}
	line = strings.TrimSpace(line)
	if utf8.RuneCountInString(line) > maxDetail {
		line = string([]rune(line)[:maxDetail])
	}
	r.Detail = &line
}

// intPtr stays a helper instead of new(v): this file compiles under the project module's language
// version, and Ebitengine v2.10.5 admits modules at go 1.25, before new(expr) existed.
func intPtr(v int) *int {
	return &v
}

// --- script -----------------------------------------------------------------------------------------

type scriptError struct {
	msg string
}

func (e *scriptError) Error() string {
	return e.msg
}

func stepErr(index int, format string, args ...any) error {
	return &scriptError{msg: fmt.Sprintf("step %d: %s", index, fmt.Sprintf(format, args...))}
}

func loadSteps(data []byte, w, h int) ([]step, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var doc struct {
		Steps []json.RawMessage `json:"steps"`
	}
	if err := dec.Decode(&doc); err != nil {
		return nil, &scriptError{msg: "script is not a JSON object with steps: " + err.Error()}
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, &scriptError{msg: "script has data after its JSON object"}
	}
	if len(doc.Steps) == 0 {
		return nil, &scriptError{msg: "script has no steps"}
	}
	if len(doc.Steps) > maxSteps {
		return nil, &scriptError{msg: fmt.Sprintf("script has %d steps; the limit is %d", len(doc.Steps), maxSteps)}
	}
	steps := make([]step, 0, len(doc.Steps))
	total := 0
	advanced := false
	shots := map[string]bool{}
	for i, raw := range doc.Steps {
		s, err := parseStep(i, raw, w, h)
		if err != nil {
			return nil, err
		}
		switch s.kind {
		case stepWait, stepType:
			if s.kind == stepWait {
				total += s.ticks
			} else {
				total += utf8.RuneCountInString(s.text)
			}
			advanced = true
		case stepKey:
			total += s.ticks + 1
			advanced = true
		case stepClick:
			total += 2
			advanced = true
		case stepScroll:
			total++
			advanced = true
		case stepShot:
			if !advanced {
				return nil, stepErr(i, "shot %q needs an earlier step that advances ticks (wait, key, type, type_env, click or scroll)", s.name)
			}
			if shots[s.name] {
				return nil, stepErr(i, "shot name %q is used twice", s.name)
			}
			shots[s.name] = true
			if len(shots) > maxShots {
				return nil, stepErr(i, "more than %d shots", maxShots)
			}
		}
		if total > maxTotalTicks {
			return nil, stepErr(i, "the script advances more than %d ticks in total", maxTotalTicks)
		}
		steps = append(steps, s)
	}
	return steps, nil
}

func parseStep(index int, raw json.RawMessage, w, h int) (step, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil || fields == nil {
		return step{}, stepErr(index, "expected an object with one action key")
	}
	names := make([]string, 0, len(fields))
	for name := range fields {
		names = append(names, name)
	}
	sort.Strings(names)
	action := ""
	for _, name := range names {
		if _, ok := actions[name]; ok {
			if action != "" {
				return step{}, stepErr(index, "expected exactly one action key, found %q and %q", action, name)
			}
			action = name
		}
	}
	if action == "" {
		return step{}, stepErr(index, "expected one action key (wait, key, hold, release, type, type_env, move, click, scroll or shot)")
	}
	for _, name := range names {
		if name == action || (name == "ticks" && action == "key") || (name == "button" && action == "click") {
			continue
		}
		return step{}, stepErr(index, "unexpected field %q in a %s step", name, action)
	}
	value := fields[action]
	s := step{kind: actions[action]}
	var err error
	switch action {
	case "wait":
		s.ticks, err = intIn(value, 1, maxWaitTicks)
		if err != nil {
			return step{}, stepErr(index, "wait: %v", err)
		}
	case "key", "hold", "release":
		s.key, err = keyName(value)
		if err != nil {
			return step{}, stepErr(index, "%s: %v", action, err)
		}
		if action == "key" {
			s.ticks = defaultKeyTicks
			if t, ok := fields["ticks"]; ok {
				s.ticks, err = intIn(t, 1, maxKeyTicks)
				if err != nil {
					return step{}, stepErr(index, "ticks: %v", err)
				}
			}
		}
	case "type":
		if err := json.Unmarshal(value, &s.text); err != nil || !isJSONString(value) {
			return step{}, stepErr(index, "type: expected a string")
		}
		if n := utf8.RuneCountInString(s.text); n < 1 || n > maxTypeRunes {
			return step{}, stepErr(index, "type: expected 1 to %d characters, got %d", maxTypeRunes, n)
		}
	case "type_env":
		return step{}, stepErr(index, "type_env must be resolved by the QA engine before the host runs")
	case "move", "click":
		s.x, s.y, err = pair(value)
		if err != nil {
			return step{}, stepErr(index, "%s: %v", action, err)
		}
		if s.x < 0 || s.x > float64(w) || s.y < 0 || s.y > float64(h) {
			return step{}, stepErr(index, "%s: point %v,%v is outside the %dx%d screen", action, s.x, s.y, w, h)
		}
		if action == "click" {
			s.button = ebiten.MouseButtonLeft
			if b, ok := fields["button"]; ok {
				var name string
				if err := json.Unmarshal(b, &name); err != nil || !isJSONString(b) {
					return step{}, stepErr(index, "button: expected left, right or middle")
				}
				button, ok := buttons[name]
				if !ok {
					return step{}, stepErr(index, "button: expected left, right or middle, got %q", name)
				}
				s.button = button
			}
		}
	case "scroll":
		s.x, s.y, err = pair(value)
		if err != nil {
			return step{}, stepErr(index, "scroll: %v", err)
		}
		if math.Abs(s.x) > maxScroll || math.Abs(s.y) > maxScroll {
			return step{}, stepErr(index, "scroll: dx and dy must be within -%d..%d", maxScroll, maxScroll)
		}
	case "shot":
		if err := json.Unmarshal(value, &s.name); err != nil || !isJSONString(value) || !shotName.MatchString(s.name) {
			return step{}, stepErr(index, "shot: expected a name matching [A-Za-z0-9_-]{1,40}")
		}
	}
	return s, nil
}

func isJSONString(raw json.RawMessage) bool {
	trimmed := bytes.TrimSpace(raw)
	return len(trimmed) > 0 && trimmed[0] == '"'
}

func number(raw json.RawMessage) (float64, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || !(trimmed[0] == '-' || (trimmed[0] >= '0' && trimmed[0] <= '9')) {
		return 0, errors.New("expected a number")
	}
	var f float64
	if err := json.Unmarshal(trimmed, &f); err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, errors.New("expected a number")
	}
	return f, nil
}

func intIn(raw json.RawMessage, low, high int) (int, error) {
	f, err := number(raw)
	if err != nil || f != math.Trunc(f) {
		return 0, fmt.Errorf("expected an integer from %d to %d", low, high)
	}
	if f < float64(low) || f > float64(high) {
		return 0, fmt.Errorf("expected an integer from %d to %d, got %v", low, high, f)
	}
	return int(f), nil
}

func pair(raw json.RawMessage) (float64, float64, error) {
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil || len(items) != 2 {
		return 0, 0, errors.New("expected [x, y]")
	}
	x, err := number(items[0])
	if err != nil {
		return 0, 0, errors.New("expected [x, y]")
	}
	y, err := number(items[1])
	if err != nil {
		return 0, 0, errors.New("expected [x, y]")
	}
	return x, y, nil
}

func keyName(raw json.RawMessage) (ebiten.Key, error) {
	var name string
	if err := json.Unmarshal(raw, &name); err != nil || !isJSONString(raw) {
		return 0, errors.New("expected an ebiten.Key name")
	}
	var key ebiten.Key
	if err := key.UnmarshalText([]byte(name)); err != nil {
		return 0, fmt.Errorf("unknown key %q", name)
	}
	return key, nil
}

// --- guest process ----------------------------------------------------------------------------------

// guestProcess owns the guest's exec.Cmd. Its reaper goroutine is the only caller of cmd.Wait; every
// other path reads the stored outcome after done is closed.
type guestProcess struct {
	cmd      *exec.Cmd
	done     chan struct{}
	exitCode int
	waitErr  error
}

func startGuest(path string, args []string, endpoint string, log *os.File) (*guestProcess, error) {
	cmd := exec.Command(path, args...)
	cmd.Env = append(os.Environ(), "EBITENGINE_VM_ENDPOINT="+endpoint)
	cmd.Stdout = log
	cmd.Stderr = log
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	g := &guestProcess{cmd: cmd, done: make(chan struct{})}
	go func() {
		g.waitErr = g.cmd.Wait()
		g.exitCode = exitCode(g.cmd.ProcessState)
		close(g.done)
	}()
	return g, nil
}

func exitCode(state *os.ProcessState) int {
	if state == nil {
		return -1
	}
	if ws, ok := state.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return 128 + int(ws.Signal())
	}
	return state.ExitCode()
}

func (g *guestProcess) exited() bool {
	select {
	case <-g.done:
		return true
	default:
		return false
	}
}

func (g *guestProcess) kill() {
	if !g.exited() {
		_ = g.cmd.Process.Kill()
	}
	<-g.done
}

// waitFor waits up to timeout for the guest to exit and reports whether it did.
func (g *guestProcess) waitFor(timeout time.Duration) bool {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-g.done:
		return true
	case <-timer.C:
		return false
	}
}

// --- host game --------------------------------------------------------------------------------------

// driver is the host: an ebiten.Game that drives one guest from a hidden window. All work happens in
// the first Update, which then terminates the host's run loop.
type driver struct {
	guest    *vmhost.GuestSession
	steps    []step
	out      string
	res      *result
	screen   *ebiten.Image
	ran      bool
	decided  bool
	finished bool
}

func (d *driver) Update() error {
	if d.ran {
		return ebiten.Termination
	}
	d.ran = true
	// Close must run inside the host's frame; it ends the session, and the guest's RunGame returns.
	defer func() {
		_ = d.guest.Close()
	}()

	scale := ebiten.Monitor().DeviceScaleFactor()
	d.res.Scale = &scale
	d.screen = ebiten.NewImage(int(float64(*logicalW)*scale), int(float64(*logicalH)*scale))
	if err := d.guest.SetOutsideScreen(d.screen); err != nil {
		d.decide("host-failed", nil, "setting the outside screen failed: "+err.Error())
		return ebiten.Termination
	}
	for i, s := range d.steps {
		if !d.run(i, s) {
			return ebiten.Termination
		}
	}
	if !d.guest.WaitTicks() || d.guest.Err() != nil {
		d.classify(len(d.steps) - 1)
		return ebiten.Termination
	}
	d.finished = true
	return ebiten.Termination
}

// run executes one step and reports whether the run continues.
func (d *driver) run(index int, s step) bool {
	g := d.guest
	waited := true
	switch s.kind {
	case stepWait:
		g.AdvanceTicks(s.ticks)
		waited = g.WaitTicks()
	case stepKey:
		g.PressKey(s.key)
		g.AdvanceTicks(s.ticks)
		g.ReleaseKey(s.key)
		g.AdvanceTicks(1)
		waited = g.WaitTicks()
	case stepHold:
		g.PressKey(s.key)
	case stepRelease:
		g.ReleaseKey(s.key)
	case stepType:
		for _, r := range s.text {
			g.TypeRune(r)
			g.AdvanceTicks(1)
		}
		waited = g.WaitTicks()
	case stepMove:
		g.MoveCursor(s.x, s.y)
	case stepClick:
		g.MoveCursor(s.x, s.y)
		g.PressMouseButton(s.button)
		g.AdvanceTicks(1)
		g.ReleaseMouseButton(s.button)
		g.AdvanceTicks(1)
		waited = g.WaitTicks()
	case stepScroll:
		g.ScrollWheel(s.x, s.y)
		g.AdvanceTicks(1)
		waited = g.WaitTicks()
	case stepShot:
		return d.shot(index, s.name)
	}
	if !waited || g.Err() != nil {
		d.classify(index)
		return false
	}
	return true
}

func (d *driver) shot(index int, name string) bool {
	g := d.guest
	g.AdvanceFrame()
	if !g.WaitFrame() {
		d.classify(index)
		return false
	}
	if !g.CompositeFrame() {
		if g.Err() != nil {
			d.classify(index)
		} else {
			d.decide("host-failed", intPtr(index), "compositing the guest frame failed")
		}
		return false
	}
	file := name + ".png"
	if err := d.dump(filepath.Join(d.out, file)); err != nil {
		d.decide("host-failed", intPtr(index), "writing "+file+" failed: "+err.Error())
		return false
	}
	d.res.Shots = append(d.res.Shots, shotRecord{Name: name, File: file, Tick: g.ProcessedTicks()})
	return true
}

// classify records why the session ended at the given step, from guest.Err().
func (d *driver) classify(index int) {
	err := d.guest.Err()
	switch {
	case err == nil:
		d.decide("guest-exited", intPtr(index), "guest ended: session closed")
	case errors.Is(err, os.ErrDeadlineExceeded):
		d.decide("timeout", intPtr(index), fmt.Sprintf("guest made no progress for %v", *idleTimeout))
	case errors.Is(err, ebiten.Termination):
		d.decide("guest-exited", intPtr(index), "guest terminated itself")
	default:
		d.decide("guest-exited", intPtr(index), "guest ended: "+err.Error())
	}
}

func (d *driver) decide(kind string, step *int, detail string) {
	d.res.set(kind, step, detail)
	d.decided = true
}

// dump writes the current screen to a PNG. ReadPixels returns premultiplied-alpha RGBA, which equals
// non-premultiplied bytes for an opaque screen.
func (d *driver) dump(path string) error {
	img := image.NewRGBA(d.screen.Bounds())
	d.screen.ReadPixels(img.Pix)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if err := png.Encode(f, img); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

func (d *driver) Draw(*ebiten.Image) {
	// The host window is hidden; the guest's frames are composited into d.screen in Update.
}

func (d *driver) Layout(outsideWidth, outsideHeight int) (int, int) {
	return outsideWidth, outsideHeight
}

// --- main -------------------------------------------------------------------------------------------

// abort holds what an asynchronous abort (the -deadline timer or a termination signal) must clean up.
type abort struct {
	mu    sync.Mutex
	guest *guestProcess
	dir   string
}

func (a *abort) exit(code int) {
	a.mu.Lock()
	if a.guest != nil && !a.guest.exited() {
		_ = a.guest.cmd.Process.Kill()
	}
	if a.dir != "" {
		_ = os.RemoveAll(a.dir)
	}
	os.Exit(code)
}

func main() {
	code, err := xmain()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
	os.Exit(code)
}

func xmain() (int, error) {
	flag.Parse()
	if *guestPath == "" || *scriptPath == "" || *outDir == "" {
		return 1, errors.New("-guest, -script and -out are required")
	}
	if *logicalW < 1 || *logicalH < 1 {
		return 1, errors.New("-w and -h must be positive")
	}
	if info, err := os.Stat(*outDir); err != nil || !info.IsDir() {
		return 1, fmt.Errorf("-out %s is not an existing directory", *outDir)
	}
	res := &result{Screen: [2]int{*logicalW, *logicalH}, Shots: []shotRecord{}}
	write := func() (int, error) {
		data, err := json.MarshalIndent(res, "", "  ")
		if err != nil {
			return 1, err
		}
		if err := os.WriteFile(filepath.Join(*outDir, "result.json"), append(data, '\n'), 0o600); err != nil {
			return 1, err
		}
		return 0, nil
	}

	data, err := os.ReadFile(*scriptPath)
	if err != nil {
		return 1, fmt.Errorf("reading the script failed: %w", err)
	}
	steps, err := loadSteps(data, *logicalW, *logicalH)
	if err != nil {
		res.set("invalid-script", nil, err.Error())
		return write()
	}

	aborter := &abort{}
	if *deadline > 0 {
		time.AfterFunc(*deadline, func() { aborter.exit(3) })
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-signals
		aborter.exit(3)
	}()

	// A short temp dir keeps the Unix socket path within the OS limit (~104 bytes on macOS).
	dir, err := os.MkdirTemp("", "qv")
	if err != nil {
		return 1, err
	}
	aborter.mu.Lock()
	aborter.dir = dir
	aborter.mu.Unlock()
	defer func() {
		_ = os.RemoveAll(dir)
	}()
	ln, err := net.Listen("unix", filepath.Join(dir, "g.sock"))
	if err != nil {
		return 1, err
	}
	defer func() {
		_ = ln.Close()
	}()
	endpoint, err := vmhost.EndpointURLFromAddr(ln.Addr())
	if err != nil {
		return 1, err
	}

	logFile, err := os.OpenFile(filepath.Join(*outDir, "guest.raw.log"), os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return 1, err
	}
	defer func() {
		_ = logFile.Close()
	}()
	guest, err := startGuest(*guestPath, flag.Args(), endpoint, logFile)
	if err != nil {
		return 1, fmt.Errorf("starting the guest failed: %w", err)
	}
	aborter.mu.Lock()
	aborter.guest = guest
	aborter.mu.Unlock()

	type accepted struct {
		conn net.Conn
		err  error
	}
	acceptCh := make(chan accepted, 1)
	go func() {
		conn, err := ln.Accept()
		acceptCh <- accepted{conn, err}
	}()
	timer := time.NewTimer(*acceptTimeout)
	defer timer.Stop()

	var session *vmhost.GuestSession
	select {
	case a := <-acceptCh:
		// The listener served this one guest: retire the endpoint so a process the guest starts cannot
		// reach this host through it.
		_ = ln.Close()
		if a.err != nil {
			guest.kill()
			res.set("host-failed", nil, "accepting the guest failed: "+a.err.Error())
			return write()
		}
		session, err = vmhost.NewGuestSession(a.conn, &vmhost.NewGuestSessionOptions{IdleTimeout: *idleTimeout})
		if err != nil {
			if guest.waitFor(handshakeExitGrace) {
				res.ExitCode = intPtr(guest.exitCode)
				res.set("guest-exited", nil, fmt.Sprintf("guest exited %d during the handshake", guest.exitCode))
				return write()
			}
			guest.kill()
			res.ExitCode = intPtr(guest.exitCode)
			res.set("handshake-failed", nil, "handshake failed: "+err.Error())
			return write()
		}
	case <-guest.done:
		res.ExitCode = intPtr(guest.exitCode)
		res.set("guest-exited", nil, fmt.Sprintf("guest exited %d before connecting", guest.exitCode))
		return write()
	case <-timer.C:
		guest.kill()
		res.ExitCode = intPtr(guest.exitCode)
		res.set("handshake-failed", nil, fmt.Sprintf("guest did not connect within %v", *acceptTimeout))
		return write()
	}

	d := &driver{guest: session, steps: steps, out: *outDir, res: res}
	ebiten.SetWindowVisible(false)
	runErr := ebiten.RunGameWithOptions(d, &ebiten.RunGameOptions{InitUnfocused: true})
	res.Ticks = session.ProcessedTicks()
	res.TPS = session.RequestedTPS()

	if !d.ran {
		// The host run ended before its first Update, so the session was never closed: the guest is
		// still attached to this host and is killed rather than awaited.
		guest.kill()
		res.ExitCode = intPtr(guest.exitCode)
		detail := "host run ended before its first update"
		if runErr != nil {
			detail += ": " + runErr.Error()
		}
		res.set("host-failed", nil, detail)
		return write()
	}

	// The closed session ends the guest's RunGame without an error, so it exits on its own.
	killed := false
	if !guest.waitFor(guestExitTimeout) {
		guest.kill()
		killed = true
	}
	res.ExitCode = intPtr(guest.exitCode)
	switch {
	case d.decided:
	case runErr != nil:
		res.set("host-failed", nil, "host run failed: "+runErr.Error())
	case !d.finished:
		res.set("host-failed", nil, "host run ended before the script finished")
	case killed:
		res.set("guest-exited", nil, "guest did not exit after the session closed")
	case guest.exitCode != 0:
		res.set("guest-exited", nil, fmt.Sprintf("guest exited %d after the last step", guest.exitCode))
	default:
		res.Result = "completed"
	}
	return write()
}
