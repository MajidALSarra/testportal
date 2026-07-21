package com.majid.countdown;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends Activity {

    private EditText inputTitle;
    private EditText inputDays;
    private EditText inputHours;
    private EditText inputMinutes;
    private TextView preview;

    private static final long DAY_MS = 86400000L;
    private static final long HOUR_MS = 3600000L;
    private static final long MIN_MS = 60000L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        inputTitle = (EditText) findViewById(R.id.input_title);
        inputDays = (EditText) findViewById(R.id.input_days);
        inputHours = (EditText) findViewById(R.id.input_hours);
        inputMinutes = (EditText) findViewById(R.id.input_minutes);
        preview = (TextView) findViewById(R.id.preview);

        SharedPreferences p = prefs();
        inputTitle.setText(p.getString(CountdownWidget.KEY_TITLE, ""));

        Button start = (Button) findViewById(R.id.btn_start);
        start.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startCountdown();
            }
        });

        refreshPreview();
    }

    private void startCountdown() {
        long days = parse(inputDays);
        long hours = parse(inputHours);
        long minutes = parse(inputMinutes);
        long totalMs = days * DAY_MS + hours * HOUR_MS + minutes * MIN_MS;

        if (totalMs <= 0L) {
            Toast.makeText(this, "Enter days, hours or minutes greater than 0",
                    Toast.LENGTH_SHORT).show();
            return;
        }

        String title = inputTitle.getText().toString().trim();
        if (TextUtils.isEmpty(title)) {
            title = "Countdown";
        }

        long target = System.currentTimeMillis() + totalMs;

        prefs().edit()
                .putLong(CountdownWidget.KEY_TARGET, target)
                .putString(CountdownWidget.KEY_TITLE, title)
                .apply();

        CountdownWidget.updateAll(this);
        refreshPreview();
        Toast.makeText(this, "Countdown started", Toast.LENGTH_SHORT).show();

        offerToPinWidget();
    }

    /** On Android 8+ ask the launcher to pin the widget with one tap. */
    private void offerToPinWidget() {
        if (Build.VERSION.SDK_INT < 26) return;
        AppWidgetManager awm = (AppWidgetManager) getSystemService(Context.APPWIDGET_SERVICE);
        if (awm == null || !awm.isRequestPinAppWidgetSupported()) return;
        ComponentName provider = new ComponentName(this, CountdownWidget.class);
        try {
            awm.requestPinAppWidget(provider, null, null);
        } catch (Exception ignored) {
            // Some launchers don't support pinning; the manual instructions still apply.
        }
    }

    private void refreshPreview() {
        SharedPreferences p = prefs();
        long target = p.getLong(CountdownWidget.KEY_TARGET, 0L);
        String title = p.getString(CountdownWidget.KEY_TITLE, "Countdown");
        if (target <= 0L) {
            preview.setText("No countdown set yet.");
            return;
        }
        long diff = target - System.currentTimeMillis();
        if (diff < 0L) diff = 0L;
        long days = diff / DAY_MS;
        long hours = (diff % DAY_MS) / HOUR_MS;
        long minutes = (diff % HOUR_MS) / MIN_MS;

        SimpleDateFormat fmt = new SimpleDateFormat("EEE, d MMM yyyy 'at' HH:mm", Locale.getDefault());
        String when = fmt.format(new Date(target));

        preview.setText(title + "\n"
                + days + " days " + hours + "h " + minutes + "m left\n"
                + "Target: " + when);
    }

    private long parse(EditText field) {
        String s = field.getText().toString().trim();
        if (TextUtils.isEmpty(s)) return 0L;
        try {
            return Long.parseLong(s);
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(CountdownWidget.PREFS, MODE_PRIVATE);
    }
}
