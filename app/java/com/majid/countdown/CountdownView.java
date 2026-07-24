package com.majid.countdown;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.os.SystemClock;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewOutlineProvider;

/** A single countdown card that animates continuously while on screen. */
public class CountdownView extends View {

    private String style = "ring";
    private int colorIndex = 0;
    private String title = "Countdown";
    private long start = 0L;
    private long target = 0L;
    private long previewRemaining = -1L;   // >=0 for the style picker previews

    private boolean running = false;

    private final Runnable frame = new Runnable() {
        @Override
        public void run() {
            invalidate();
            if (running) postOnAnimation(this);
        }
    };

    public CountdownView(Context c) { super(c); init(); }
    public CountdownView(Context c, AttributeSet a) { super(c, a); init(); }

    private void init() {
        setElevation(dp(5));
        setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline o) {
                o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), v.getHeight() * 0.13f);
            }
        });
        setClipToOutline(true);
    }

    public void bind(Countdown c) {
        this.style = c.style;
        this.colorIndex = c.colorIndex;
        this.title = c.title;
        this.start = c.start;
        this.target = c.target;
        this.previewRemaining = -1L;
        invalidate();
    }

    /** For the style/colour preview tiles in the editor. */
    public void preview(String style, int colorIndex, long remaining, String title) {
        this.style = style;
        this.colorIndex = colorIndex;
        this.previewRemaining = remaining;
        this.title = title;
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        running = true;
        postOnAnimation(frame);
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        running = false;
        removeCallbacks(frame);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        long remaining, total;
        if (previewRemaining >= 0) {
            remaining = previewRemaining;
            total = Math.max(previewRemaining * 2, 1);
        } else {
            remaining = Math.max(0, target - System.currentTimeMillis());
            total = Math.max(1, target - start);
        }
        CountdownRenderer.draw(canvas, getWidth(), getHeight(), style, colorIndex,
                title, remaining, total, SystemClock.uptimeMillis(), false);
    }

    private float dp(float v) {
        return v * getResources().getDisplayMetrics().density;
    }
}
