package com.majid.countdown;

import org.json.JSONException;
import org.json.JSONObject;

/** One countdown: a title, when it started, when it ends, and how it looks. */
public class Countdown {

    public long id;
    public String title;
    public long start;      // when the countdown was (re)started, ms
    public long target;     // when it finishes, ms
    public String style;    // "ring" | "boxes" | "bars" | "triangles" | "dots"
    public int colorIndex;  // index into CountdownRenderer.PALETTES

    public Countdown() {
        this.style = "ring";
        this.colorIndex = 0;
    }

    public long totalMs() {
        long t = target - start;
        return t > 0 ? t : 1;
    }

    public long remainingMs() {
        long r = target - System.currentTimeMillis();
        return r > 0 ? r : 0;
    }

    public boolean finished() {
        return System.currentTimeMillis() >= target;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject o = new JSONObject();
        o.put("id", id);
        o.put("title", title);
        o.put("start", start);
        o.put("target", target);
        o.put("style", style);
        o.put("color", colorIndex);
        return o;
    }

    public static Countdown fromJson(JSONObject o) {
        Countdown c = new Countdown();
        c.id = o.optLong("id", System.currentTimeMillis());
        c.title = o.optString("title", "Countdown");
        c.start = o.optLong("start", System.currentTimeMillis());
        c.target = o.optLong("target", c.start);
        c.style = o.optString("style", "ring");
        c.colorIndex = o.optInt("color", 0);
        return c;
    }
}
