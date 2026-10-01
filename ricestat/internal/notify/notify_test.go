package notify

import "testing"

func TestMarkupEscapado(t *testing.T) {
	got := markup.Replace(`fix: <a href="http://x">clique</a> & pronto`)
	want := `fix: &lt;a href="http://x"&gt;clique&lt;/a&gt; &amp; pronto`
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}
