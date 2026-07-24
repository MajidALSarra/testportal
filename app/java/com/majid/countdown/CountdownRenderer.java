package com.majid.countdown;

import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;

/**
 * Draws a countdown card in one of five styles onto a Canvas. Both the in-app
 * animated view and the home-screen widget bitmap use this, so they always
 * look identical. {@code clock} drives animation (pass a fixed value for a
 * still frame, e.g. in the widget).
 */
public class CountdownRenderer {

    public static final String[] STYLE_IDS =
            {"ring", "boxes", "bars", "triangles", "dots"};
    public static final String[] STYLE_NAMES =
            {"Ring", "Boxes", "Bars", "Triangles", "Dots"};

    // Each palette: {gradientTop, gradientBottom}. Content is always white.
    public static final int[][] PALETTES = {
            {0xFF7C4DFF, 0xFF4D8BFF},   // violet -> blue
            {0xFFFF6B6B, 0xFFFFA84D},   // coral -> orange
            {0xFF11998E, 0xFF38EF7D},   // teal -> green
            {0xFFF857A6, 0xFFFF5858},   // pink -> red
            {0xFF2B5876, 0xFF4E4376},   // slate -> indigo
            {0xFFF7971E, 0xFFFFD200},   // amber -> gold
    };

    private static final long SEC = 1000L, MIN = 60000L, HOUR = 3600000L, DAY = 86400000L;
    private static final int WHITE = 0xFFFFFFFF;
    private static final int TRACK = 0x30FFFFFF;
    private static final int FILL_SOFT = 0x26FFFFFF;

    public static int styleIndex(String id) {
        for (int i = 0; i < STYLE_IDS.length; i++) {
            if (STYLE_IDS[i].equals(id)) return i;
        }
        return 0;
    }

    public static void draw(Canvas c, float w, float h, String style, int colorIndex,
                            String title, long remaining, long total, long clock, boolean widget) {
        int[] pal = PALETTES[((colorIndex % PALETTES.length) + PALETTES.length) % PALETTES.length];
        float radius = h * 0.13f;

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);

        // Card background gradient.
        RectF card = new RectF(0, 0, w, h);
        p.setShader(new LinearGradient(0, 0, 0, h, pal[0], pal[1], Shader.TileMode.CLAMP));
        c.drawRoundRect(card, radius, radius, p);
        p.setShader(null);

        // A soft diagonal sheen for depth.
        p.setColor(0x14FFFFFF);
        c.save();
        c.clipRect(card);
        Path sheen = new Path();
        sheen.moveTo(-w * 0.1f, 0);
        sheen.lineTo(w * 0.55f, 0);
        sheen.lineTo(w * 0.30f, h);
        sheen.lineTo(-w * 0.1f, h);
        sheen.close();
        c.drawPath(sheen, p);
        c.restore();

        float pad = h * 0.11f;

        // Title.
        Paint tp = text(WHITE, h * 0.115f, true);
        tp.setAlpha(235);
        String t = title == null ? "" : title;
        t = ellipsize(t, tp, w - pad * 2);
        c.drawText(t, pad, pad + h * 0.10f, tp);

        // Sub line (target-relative summary) top-right.
        long[] u = units(remaining);
        Paint sp2 = text(WHITE, h * 0.075f, false);
        sp2.setAlpha(180);
        sp2.setTextAlign(Paint.Align.RIGHT);
        String sub = remaining <= 0 ? "FINISHED" : (u[0] + "d left");
        c.drawText(sub, w - pad, pad + h * 0.085f, sp2);

        float top = pad + h * 0.18f;
        RectF area = new RectF(pad, top, w - pad, h - pad * 0.6f);

        int si = styleIndex(style);
        switch (si) {
            case 1: drawBoxes(c, area, remaining, total, clock, widget); break;
            case 2: drawBars(c, area, remaining, total, clock, widget); break;
            case 3: drawTriangles(c, area, remaining, total, clock, widget); break;
            case 4: drawDots(c, area, remaining, total, clock, widget); break;
            default: drawRing(c, area, remaining, total, clock, widget); break;
        }
    }

    // ---------- styles ----------

    private static void drawRing(Canvas c, RectF a, long remaining, long total,
                                 long clock, boolean widget) {
        float cx = a.centerX();
        float cy = a.centerY();
        float r = Math.min(a.width(), a.height()) * 0.44f;
        float stroke = r * 0.16f;
        RectF ring = new RectF(cx - r, cy - r, cx + r, cy + r);

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(stroke);
        p.setStrokeCap(Paint.Cap.ROUND);

        p.setColor(TRACK);
        c.drawArc(ring, 0, 360, false, p);

        float frac = total > 0 ? clamp((float) remaining / (float) total) : 0f;
        float sweep = 360f * frac;
        p.setColor(WHITE);
        c.drawArc(ring, -90, sweep, false, p);

        // Glowing head of the arc.
        double ang = Math.toRadians(-90 + sweep);
        float hx = cx + (float) Math.cos(ang) * r;
        float hy = cy + (float) Math.sin(ang) * r;
        float pulse = 1f + 0.25f * (float) Math.sin(clock / 320.0);
        Paint glow = new Paint(Paint.ANTI_ALIAS_FLAG);
        glow.setColor(0x66FFFFFF);
        c.drawCircle(hx, hy, stroke * 0.9f * pulse, glow);
        glow.setColor(WHITE);
        c.drawCircle(hx, hy, stroke * 0.5f, glow);

        long[] u = units(remaining);
        Paint big = text(WHITE, r * 0.85f, true);
        big.setTextAlign(Paint.Align.CENTER);
        c.drawText(Long.toString(u[0]), cx, cy + r * 0.18f, big);
        Paint lab = text(WHITE, r * 0.24f, true);
        lab.setTextAlign(Paint.Align.CENTER);
        lab.setAlpha(200);
        lab.setLetterSpacing(0.18f);
        c.drawText("DAYS", cx, cy + r * 0.52f, lab);

        Paint hms = text(WHITE, r * 0.26f, false);
        hms.setTextAlign(Paint.Align.CENTER);
        hms.setAlpha(220);
        c.drawText(two(u[1]) + ":" + two(u[2]) + ":" + two(u[3]), cx, a.bottom, hms);
    }

    private static void drawBoxes(Canvas c, RectF a, long remaining, long total,
                                  long clock, boolean widget) {
        long[] u = units(remaining);
        String[] vals = {Long.toString(u[0]), two(u[1]), two(u[2]), two(u[3])};
        String[] labs = {"DAYS", "HRS", "MIN", "SEC"};
        float gap = a.width() * 0.035f;
        float bw = (a.width() - gap * 3) / 4f;
        float bh = Math.min(bw * 1.15f, a.height());
        float y = a.centerY() - bh / 2f;
        float frac = remaining > 0 ? (float) (remaining % SEC) / 1000f : 0f;

        Paint box = new Paint(Paint.ANTI_ALIAS_FLAG);
        for (int i = 0; i < 4; i++) {
            float x = a.left + i * (bw + gap);
            float scale = 1f;
            if (i == 3 && !widget) scale = 1f + 0.05f * (float) Math.sin(clock / 150.0);
            float dx = bw * (scale - 1f) / 2f;
            float dy = bh * (scale - 1f) / 2f;
            RectF rb = new RectF(x - dx, y - dy, x + bw + dx, y + bh + dy);
            float rad = bw * 0.22f;

            box.setColor(FILL_SOFT);
            c.drawRoundRect(rb, rad, rad, box);
            box.setColor(0x18FFFFFF);
            c.drawRoundRect(new RectF(rb.left, rb.top, rb.right, rb.top + bh * 0.42f), rad, rad, box);

            Paint num = text(WHITE, bh * 0.42f, true);
            num.setTextAlign(Paint.Align.CENTER);
            c.drawText(vals[i], rb.centerX(), rb.centerY() + bh * 0.10f, num);
            Paint lab = text(WHITE, bh * 0.15f, true);
            lab.setTextAlign(Paint.Align.CENTER);
            lab.setAlpha(190);
            lab.setLetterSpacing(0.08f);
            c.drawText(labs[i], rb.centerX(), rb.bottom - bh * 0.10f, lab);

            // Sub-second progress line under the seconds box.
            if (i == 3) {
                Paint pl = new Paint(Paint.ANTI_ALIAS_FLAG);
                pl.setColor(WHITE);
                float lw = bw * (1f - frac);
                c.drawRoundRect(new RectF(rb.left, rb.bottom - bh * 0.05f,
                        rb.left + lw, rb.bottom), rad * 0.3f, rad * 0.3f, pl);
            }
        }
    }

    private static void drawBars(Canvas c, RectF a, long remaining, long total,
                                 long clock, boolean widget) {
        long[] u = units(remaining);
        long totalDays = Math.max(1, total / DAY);
        float[] fracs = {
                clamp((float) u[0] / (float) totalDays),
                clamp((float) (u[1] + (u[2] / 60f)) / 24f),
                clamp((float) (u[2] + (u[3] / 60f)) / 60f),
                clamp((float) (u[3] + (remaining % SEC) / 1000f) / 60f)
        };
        String[] labs = {"D", "H", "M", "S"};
        String[] vals = {Long.toString(u[0]), two(u[1]), two(u[2]), two(u[3])};

        float rowH = a.height() / 4f;
        float barH = rowH * 0.42f;
        float labW = a.width() * 0.10f;
        float valW = a.width() * 0.16f;
        float x0 = a.left + labW;
        float x1 = a.right - valW;

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        for (int i = 0; i < 4; i++) {
            float cy = a.top + rowH * i + rowH / 2f;
            Paint lab = text(WHITE, barH * 0.95f, true);
            lab.setAlpha(210);
            c.drawText(labs[i], a.left, cy + barH * 0.35f, lab);

            RectF track = new RectF(x0, cy - barH / 2f, x1, cy + barH / 2f);
            p.setColor(TRACK);
            c.drawRoundRect(track, barH / 2f, barH / 2f, p);

            float fillW = (x1 - x0) * fracs[i];
            RectF fill = new RectF(x0, track.top, x0 + Math.max(fillW, barH), track.bottom);
            p.setColor(WHITE);
            c.drawRoundRect(fill, barH / 2f, barH / 2f, p);

            // Moving shimmer along the fill.
            if (!widget && fillW > barH) {
                float sh = (float) ((clock / 900.0 + i * 0.2) % 1.0);
                float sx = x0 + sh * (fill.right - x0);
                Paint sm = new Paint(Paint.ANTI_ALIAS_FLAG);
                sm.setColor(0x66FFFFFF);
                c.save();
                c.clipRect(fill);
                c.drawCircle(sx, cy, barH * 0.9f, sm);
                c.restore();
            }

            Paint val = text(WHITE, barH * 1.0f, true);
            val.setTextAlign(Paint.Align.RIGHT);
            c.drawText(vals[i], a.right, cy + barH * 0.35f, val);
        }
    }

    private static void drawTriangles(Canvas c, RectF a, long remaining, long total,
                                      long clock, boolean widget) {
        long[] u = units(remaining);
        long totalDays = Math.max(1, total / DAY);
        float[] fracs = {
                clamp((float) u[0] / (float) totalDays),
                clamp((float) (u[1] + u[2] / 60f) / 24f),
                clamp((float) (u[2] + u[3] / 60f) / 60f),
                clamp((float) (u[3] + (remaining % SEC) / 1000f) / 60f)
        };
        String[] labs = {"D", "H", "M", "S"};
        String[] vals = {Long.toString(u[0]), two(u[1]), two(u[2]), two(u[3])};

        float gap = a.width() * 0.05f;
        float tw = (a.width() - gap * 3) / 4f;
        float th = Math.min(a.height() * 0.72f, tw * 1.25f);
        float baseY = a.top + th;

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        for (int i = 0; i < 4; i++) {
            float x = a.left + i * (tw + gap);
            float apexX = x + tw / 2f;
            Path tri = new Path();
            tri.moveTo(apexX, a.top);
            tri.lineTo(x + tw, baseY);
            tri.lineTo(x, baseY);
            tri.close();

            p.setColor(TRACK);
            c.drawPath(tri, p);

            // Liquid fill rising from the base by fraction, with a wave surface.
            float level = baseY - th * fracs[i];
            c.save();
            c.clipPath(tri);
            Path wave = new Path();
            wave.moveTo(x - 2, baseY + 2);
            wave.lineTo(x - 2, level);
            float amp = th * 0.03f;
            int steps = 10;
            for (int s = 0; s <= steps; s++) {
                float wx = x + (tw + 4) * s / steps - 2;
                float phase = widget ? 0f : (float) (clock / 300.0);
                float wy = level + amp * (float) Math.sin(phase + s * 0.9);
                wave.lineTo(wx, wy);
            }
            wave.lineTo(x + tw + 2, baseY + 2);
            wave.close();
            p.setColor(WHITE);
            c.drawPath(wave, p);
            c.restore();

            // Outline.
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(tw * 0.02f);
            p.setColor(0x55FFFFFF);
            c.drawPath(tri, p);
            p.setStyle(Paint.Style.FILL);

            Paint val = text(WHITE, tw * 0.34f, true);
            val.setTextAlign(Paint.Align.CENTER);
            c.drawText(vals[i], apexX, baseY - th * 0.10f, val);
            Paint lab = text(WHITE, tw * 0.22f, true);
            lab.setTextAlign(Paint.Align.CENTER);
            lab.setAlpha(200);
            c.drawText(labs[i], apexX, a.bottom, lab);
        }
    }

    private static void drawDots(Canvas c, RectF a, long remaining, long total,
                                 long clock, boolean widget) {
        float cx = a.centerX();
        float cy = a.centerY();
        float r = Math.min(a.width(), a.height()) * 0.44f;
        int n = 36;
        float frac = total > 0 ? clamp((float) remaining / (float) total) : 0f;
        int lit = Math.round(n * frac);
        float dot = r * 0.09f;

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        for (int i = 0; i < n; i++) {
            double ang = -Math.PI / 2 + 2 * Math.PI * i / n;
            float dx = cx + (float) Math.cos(ang) * r;
            float dy = cy + (float) Math.sin(ang) * r;
            if (i < lit) {
                p.setColor(WHITE);
                c.drawCircle(dx, dy, dot, p);
            } else {
                p.setColor(TRACK);
                c.drawCircle(dx, dy, dot * 0.8f, p);
            }
        }

        // Orbiting comet.
        if (!widget) {
            double oa = -Math.PI / 2 + 2 * Math.PI * ((clock / 2400.0) % 1.0);
            float ox = cx + (float) Math.cos(oa) * r;
            float oy = cy + (float) Math.sin(oa) * r;
            p.setColor(0x88FFFFFF);
            c.drawCircle(ox, oy, dot * 1.8f, p);
            p.setColor(WHITE);
            c.drawCircle(ox, oy, dot * 1.0f, p);
        }

        long[] u = units(remaining);
        Paint big = text(WHITE, r * 0.8f, true);
        big.setTextAlign(Paint.Align.CENTER);
        c.drawText(Long.toString(u[0]), cx, cy + r * 0.12f, big);
        Paint lab = text(WHITE, r * 0.22f, true);
        lab.setTextAlign(Paint.Align.CENTER);
        lab.setAlpha(200);
        lab.setLetterSpacing(0.15f);
        c.drawText("DAYS", cx, cy + r * 0.42f, lab);
        Paint hms = text(WHITE, r * 0.22f, false);
        hms.setTextAlign(Paint.Align.CENTER);
        hms.setAlpha(210);
        c.drawText(two(u[1]) + ":" + two(u[2]) + ":" + two(u[3]), cx, a.bottom, hms);
    }

    // ---------- helpers ----------

    private static long[] units(long ms) {
        if (ms < 0) ms = 0;
        long d = ms / DAY;
        long h = (ms % DAY) / HOUR;
        long m = (ms % HOUR) / MIN;
        long s = (ms % MIN) / SEC;
        return new long[]{d, h, m, s};
    }

    private static Paint text(int color, float size, boolean bold) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(color);
        p.setTextSize(size);
        p.setTypeface(bold ? Typeface.create(Typeface.DEFAULT, Typeface.BOLD) : Typeface.DEFAULT);
        return p;
    }

    private static String two(long v) {
        return v < 10 ? "0" + v : Long.toString(v);
    }

    private static float clamp(float f) {
        return f < 0 ? 0 : (f > 1 ? 1 : f);
    }

    private static String ellipsize(String s, Paint p, float maxW) {
        if (p.measureText(s) <= maxW) return s;
        String ell = "…";
        while (s.length() > 1 && p.measureText(s + ell) > maxW) {
            s = s.substring(0, s.length() - 1);
        }
        return s + ell;
    }
}
