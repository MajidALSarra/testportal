package com.majid.countdown;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;

/** Shown when a widget is dropped: lets the user pick which countdown it shows. */
public class WidgetConfigActivity extends Activity {

    private int widgetId = AppWidgetManager.INVALID_APPWIDGET_ID;
    private Store store;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setResult(RESULT_CANCELED);
        store = new Store(this);

        Bundle extras = getIntent().getExtras();
        if (extras != null) {
            widgetId = extras.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID);
        }
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish();
            return;
        }
        getWindow().getDecorView().setBackgroundColor(0xFFF2F1F8);
        build();
    }

    @Override
    protected void onResume() {
        super.onResume();
        build();
    }

    private void build() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(24), dp(20), dp(24));

        TextView head = new TextView(this);
        head.setText("Show which countdown?");
        head.setTextColor(0xFF1B1A2E);
        head.setTextSize(22);
        head.setTypeface(Typeface.DEFAULT_BOLD);
        head.setPadding(0, 0, 0, dp(16));
        root.addView(head);

        List<Countdown> items = store.all();
        if (items.isEmpty()) {
            TextView none = new TextView(this);
            none.setText("You have no countdowns yet. Create one first, then add the widget again.");
            none.setTextColor(0xFF8A889C);
            none.setTextSize(15);
            none.setPadding(0, 0, 0, dp(16));
            root.addView(none);

            Button create = new Button(this);
            create.setText("Open app");
            create.setAllCaps(false);
            create.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    startActivity(new Intent(WidgetConfigActivity.this, MainActivity.class));
                }
            });
            root.addView(create);
        } else {
            for (int i = 0; i < items.size(); i++) {
                final Countdown c = items.get(i);
                CountdownView cv = new CountdownView(this);
                cv.bind(c);
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, dp(150));
                lp.bottomMargin = dp(14);
                cv.setLayoutParams(lp);
                cv.setOnClickListener(new View.OnClickListener() {
                    @Override public void onClick(View v) { choose(c); }
                });
                root.addView(cv);
            }
        }

        scroll.addView(root);
        setContentView(scroll);
    }

    private void choose(Countdown c) {
        store.bindWidget(widgetId, c.id);
        AppWidgetManager mgr = AppWidgetManager.getInstance(this);
        CountdownWidget.updateAll(this);
        Intent result = new Intent();
        result.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId);
        setResult(RESULT_OK, result);
        finish();
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
