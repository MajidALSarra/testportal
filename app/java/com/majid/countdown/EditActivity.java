package com.majid.countdown;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/** Create or edit a countdown: title, duration, style and colour. */
public class EditActivity extends Activity {

    private Store store;
    private long editingId = -1L;

    private EditText title, days, hours, minutes;
    private int selStyle = 0;
    private int selColor = 0;

    private final CountdownView[] stylePreviews = new CountdownView[CountdownRenderer.STYLE_IDS.length];
    private final FrameLayout[] styleWraps = new FrameLayout[CountdownRenderer.STYLE_IDS.length];
    private final View[] colorDots = new View[CountdownRenderer.PALETTES.length];

    private static final long SAMPLE = 12L * 86400000L + 3L * 3600000L + 40L * 60000L;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        store = new Store(this);
        getWindow().getDecorView().setBackgroundColor(0xFFF2F1F8);

        Countdown existing = null;
        editingId = getIntent().getLongExtra("id", -1L);
        if (editingId != -1L) existing = store.get(editingId);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(22), dp(20), dp(30));

        TextView head = new TextView(this);
        head.setText(existing == null ? "New countdown" : "Edit countdown");
        head.setTextColor(0xFF1B1A2E);
        head.setTextSize(24);
        head.setTypeface(Typeface.DEFAULT_BOLD);
        head.setPadding(0, 0, 0, dp(18));
        root.addView(head);

        root.addView(label("TITLE"));
        title = field(InputType.TYPE_CLASS_TEXT);
        title.setHint("e.g. Trip to Tokyo");
        root.addView(title);

        root.addView(spacer(dp(16)));
        root.addView(label("TIME FROM NOW"));
        LinearLayout timeRow = new LinearLayout(this);
        timeRow.setOrientation(LinearLayout.HORIZONTAL);
        days = numberCol(timeRow, "DAYS");
        hours = numberCol(timeRow, "HOURS");
        minutes = numberCol(timeRow, "MINUTES");
        root.addView(timeRow);

        root.addView(spacer(dp(20)));
        root.addView(label("APPEARANCE"));
        root.addView(buildStyleRow());

        root.addView(spacer(dp(18)));
        root.addView(label("COLOUR"));
        root.addView(buildColorRow());

        root.addView(spacer(dp(26)));
        Button save = new Button(this);
        save.setText("Save countdown");
        save.setAllCaps(false);
        save.setTextColor(Color.WHITE);
        save.setTextSize(17);
        save.setTypeface(Typeface.DEFAULT_BOLD);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xFF7C4DFF);
        bg.setCornerRadius(dp(16));
        save.setBackground(bg);
        save.setPadding(0, dp(14), 0, dp(14));
        save.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { onSave(); }
        });
        root.addView(save, matchW());

        if (existing != null) {
            root.addView(spacer(dp(12)));
            Button del = new Button(this);
            del.setText("Delete");
            del.setAllCaps(false);
            del.setTextColor(0xFFE23B4E);
            del.setTextSize(16);
            GradientDrawable db = new GradientDrawable();
            db.setColor(0x00000000);
            db.setStroke(dp(1), 0x33E23B4E);
            db.setCornerRadius(dp(16));
            del.setBackground(db);
            del.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    store.delete(editingId);
                    CountdownWidget.updateAll(EditActivity.this);
                    finish();
                }
            });
            root.addView(del, matchW());
        }

        scroll.addView(root);
        setContentView(scroll);

        // Prefill.
        if (existing != null) {
            title.setText(existing.title);
            long rem = Math.max(0, existing.target - System.currentTimeMillis());
            days.setText(Long.toString(rem / 86400000L));
            hours.setText(Long.toString((rem % 86400000L) / 3600000L));
            minutes.setText(Long.toString((rem % 3600000L) / 60000L));
            selStyle = CountdownRenderer.styleIndex(existing.style);
            selColor = existing.colorIndex % CountdownRenderer.PALETTES.length;
        }
        refreshSelection();
    }

    // ---- builders ----

    private View buildStyleRow() {
        HorizontalScrollView hs = new HorizontalScrollView(this);
        hs.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, dp(6), 0, dp(6));
        for (int i = 0; i < CountdownRenderer.STYLE_IDS.length; i++) {
            final int idx = i;
            FrameLayout wrap = new FrameLayout(this);
            wrap.setPadding(dp(6), dp(6), dp(6), dp(6));
            LinearLayout col = new LinearLayout(this);
            col.setOrientation(LinearLayout.VERTICAL);

            CountdownView pv = new CountdownView(this);
            pv.preview(CountdownRenderer.STYLE_IDS[i], selColor, SAMPLE,
                    CountdownRenderer.STYLE_NAMES[i]);
            col.addView(pv, new LinearLayout.LayoutParams(dp(150), dp(150)));

            TextView name = new TextView(this);
            name.setText(CountdownRenderer.STYLE_NAMES[i]);
            name.setTextColor(0xFF56546A);
            name.setTextSize(13);
            name.setGravity(Gravity.CENTER);
            name.setPadding(0, dp(6), 0, 0);
            col.addView(name, new LinearLayout.LayoutParams(dp(150),
                    ViewGroup.LayoutParams.WRAP_CONTENT));

            wrap.addView(col);
            wrap.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    selStyle = idx;
                    refreshSelection();
                }
            });
            stylePreviews[i] = pv;
            styleWraps[i] = wrap;
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.rightMargin = dp(6);
            row.addView(wrap, lp);
        }
        hs.addView(row);
        return hs;
    }

    private View buildColorRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(0, dp(6), 0, dp(6));
        for (int i = 0; i < CountdownRenderer.PALETTES.length; i++) {
            final int idx = i;
            View dot = new View(this);
            GradientDrawable g = new GradientDrawable();
            g.setShape(GradientDrawable.OVAL);
            g.setColors(new int[]{CountdownRenderer.PALETTES[i][0], CountdownRenderer.PALETTES[i][1]});
            g.setGradientType(GradientDrawable.LINEAR_GRADIENT);
            dot.setBackground(g);
            dot.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    selColor = idx;
                    for (int k = 0; k < stylePreviews.length; k++) {
                        stylePreviews[k].preview(CountdownRenderer.STYLE_IDS[k], selColor,
                                SAMPLE, CountdownRenderer.STYLE_NAMES[k]);
                    }
                    refreshSelection();
                }
            });
            colorDots[i] = dot;
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(44), dp(44));
            lp.rightMargin = dp(12);
            row.addView(dot, lp);
        }
        return row;
    }

    private void refreshSelection() {
        for (int i = 0; i < styleWraps.length; i++) {
            GradientDrawable g = new GradientDrawable();
            g.setCornerRadius(dp(20));
            if (i == selStyle) {
                g.setColor(0x1A7C4DFF);
                g.setStroke(dp(2), 0xFF7C4DFF);
            } else {
                g.setColor(0x00000000);
            }
            styleWraps[i].setBackground(g);
        }
        for (int i = 0; i < colorDots.length; i++) {
            GradientDrawable g = new GradientDrawable();
            g.setShape(GradientDrawable.OVAL);
            g.setColors(new int[]{CountdownRenderer.PALETTES[i][0], CountdownRenderer.PALETTES[i][1]});
            g.setGradientType(GradientDrawable.LINEAR_GRADIENT);
            if (i == selColor) g.setStroke(dp(3), 0xFF1B1A2E);
            colorDots[i].setBackground(g);
        }
    }

    private void onSave() {
        long d = parse(days), h = parse(hours), m = parse(minutes);
        long dur = d * 86400000L + h * 3600000L + m * 60000L;
        if (dur <= 0L) {
            Toast.makeText(this, "Enter days, hours or minutes greater than 0",
                    Toast.LENGTH_SHORT).show();
            return;
        }
        String t = title.getText().toString().trim();
        if (TextUtils.isEmpty(t)) t = "Countdown";

        Countdown c = editingId != -1L ? store.get(editingId) : null;
        if (c == null) {
            c = new Countdown();
            c.id = System.currentTimeMillis();
        }
        c.title = t;
        c.start = System.currentTimeMillis();
        c.target = c.start + dur;
        c.style = CountdownRenderer.STYLE_IDS[selStyle];
        c.colorIndex = selColor;
        store.put(c);

        CountdownWidget.updateAll(this);
        offerPin(c);
        finish();
    }

    private void offerPin(Countdown c) {
        if (Build.VERSION.SDK_INT < 26) return;
        AppWidgetManager awm = (AppWidgetManager) getSystemService(Context.APPWIDGET_SERVICE);
        if (awm == null || !awm.isRequestPinAppWidgetSupported()) return;
        try {
            awm.requestPinAppWidget(new ComponentName(this, CountdownWidget.class), null, null);
        } catch (Exception ignored) {
        }
    }

    // ---- small helpers ----

    private TextView label(String s) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(0xFF8A889C);
        t.setTextSize(12);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setLetterSpacing(0.08f);
        t.setPadding(0, 0, 0, dp(6));
        return t;
    }

    private EditText field(int inputType) {
        EditText e = new EditText(this);
        e.setInputType(inputType);
        e.setTextColor(0xFF1B1A2E);
        e.setHintTextColor(0xFFB4B2C4);
        e.setTextSize(16);
        GradientDrawable g = new GradientDrawable();
        g.setColor(Color.WHITE);
        g.setCornerRadius(dp(12));
        g.setStroke(dp(1), 0xFFDCDAE8);
        e.setBackground(g);
        e.setPadding(dp(14), dp(12), dp(14), dp(12));
        return e;
    }

    private EditText numberCol(LinearLayout parent, String lab) {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        TextView l = new TextView(this);
        l.setText(lab);
        l.setTextColor(0xFF8A889C);
        l.setTextSize(11);
        l.setPadding(0, 0, 0, dp(4));
        col.addView(l);
        EditText e = field(InputType.TYPE_CLASS_NUMBER);
        e.setHint("0");
        e.setGravity(Gravity.CENTER);
        e.setTextSize(18);
        col.addView(e, matchW());
        LinearLayout.LayoutParams lp =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        if (parent.getChildCount() > 0) lp.leftMargin = dp(10);
        parent.addView(col, lp);
        return e;
    }

    private View spacer(int h) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, h));
        return v;
    }

    private LinearLayout.LayoutParams matchW() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private long parse(EditText e) {
        String s = e.getText().toString().trim();
        if (TextUtils.isEmpty(s)) return 0L;
        try { return Long.parseLong(s); } catch (NumberFormatException x) { return 0L; }
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
