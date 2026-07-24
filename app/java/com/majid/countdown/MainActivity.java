package com.majid.countdown;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;

/** Home screen of the app: every countdown drawn in its own animated style. */
public class MainActivity extends Activity {

    private LinearLayout list;
    private TextView empty;
    private Store store;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        store = new Store(this);
        getWindow().getDecorView().setBackgroundColor(0xFFF2F1F8);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(20), dp(18), dp(28));

        // Header row.
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView h = new TextView(this);
        h.setText("My Countdowns");
        h.setTextColor(0xFF1B1A2E);
        h.setTextSize(26);
        h.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams hlp =
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        header.addView(h, hlp);

        Button add = new Button(this);
        add.setText("+");
        add.setTextSize(26);
        add.setTextColor(Color.WHITE);
        add.setTypeface(Typeface.DEFAULT_BOLD);
        add.setAllCaps(false);
        add.setPadding(0, 0, 0, dp(4));
        GradientDrawable fab = new GradientDrawable();
        fab.setShape(GradientDrawable.OVAL);
        fab.setColor(0xFF7C4DFF);
        add.setBackground(fab);
        add.setElevation(dp(4));
        add.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(MainActivity.this, EditActivity.class));
            }
        });
        header.addView(add, new LinearLayout.LayoutParams(dp(52), dp(52)));
        root.addView(header);

        TextView sub = new TextView(this);
        sub.setText("Tap a card to edit · long-press to delete");
        sub.setTextColor(0xFF8A889C);
        sub.setTextSize(13);
        sub.setPadding(dp(2), dp(4), 0, dp(16));
        root.addView(sub);

        empty = new TextView(this);
        empty.setText("No countdowns yet.\nTap + to create your first one.");
        empty.setTextColor(0xFF9A98AC);
        empty.setTextSize(16);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(0, dp(80), 0, 0);
        root.addView(empty);

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        root.addView(list);

        scroll.addView(root);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        rebuild();
    }

    private void rebuild() {
        list.removeAllViews();
        List<Countdown> items = store.all();
        empty.setVisibility(items.isEmpty() ? View.VISIBLE : View.GONE);

        for (int i = 0; i < items.size(); i++) {
            final Countdown c = items.get(i);
            CountdownView cv = new CountdownView(this);
            cv.bind(c);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, dp(172));
            lp.bottomMargin = dp(16);
            cv.setLayoutParams(lp);
            cv.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    Intent it = new Intent(MainActivity.this, EditActivity.class);
                    it.putExtra("id", c.id);
                    startActivity(it);
                }
            });
            cv.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    confirmDelete(c);
                    return true;
                }
            });
            list.addView(cv);
        }
    }

    private void confirmDelete(final Countdown c) {
        new AlertDialog.Builder(this)
                .setTitle("Delete countdown")
                .setMessage("Remove \"" + c.title + "\"?")
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Delete", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface d, int w) {
                        store.delete(c.id);
                        CountdownWidget.updateAll(MainActivity.this);
                        rebuild();
                    }
                })
                .show();
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
