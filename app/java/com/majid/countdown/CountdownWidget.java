package com.majid.countdown;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.widget.RemoteViews;

/**
 * Home-screen widget that shows how many days / hours / minutes are left
 * until the target time the user set in the app.
 */
public class CountdownWidget extends AppWidgetProvider {

    public static final String PREFS = "countdown";
    public static final String KEY_TARGET = "target";
    public static final String KEY_TITLE = "title";
    public static final String ACTION_TICK = "com.majid.countdown.ACTION_TICK";

    private static final long DAY_MS = 86400000L;
    private static final long HOUR_MS = 3600000L;
    private static final long MIN_MS = 60000L;

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        updateAll(context);
        scheduleTick(context);
    }

    @Override
    public void onEnabled(Context context) {
        scheduleTick(context);
    }

    @Override
    public void onDisabled(Context context) {
        cancelTick(context);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (intent != null && ACTION_TICK.equals(intent.getAction())) {
            updateAll(context);
            scheduleTick(context);
        }
    }

    /** Refreshes every placed instance of the widget. */
    public static void updateAll(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        ComponentName cn = new ComponentName(context, CountdownWidget.class);
        int[] ids = manager.getAppWidgetIds(cn);
        for (int i = 0; i < ids.length; i++) {
            manager.updateAppWidget(ids[i], buildViews(context));
        }
    }

    private static RemoteViews buildViews(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long target = p.getLong(KEY_TARGET, 0L);
        String title = p.getString(KEY_TITLE, "Countdown");

        RemoteViews rv = new RemoteViews(context.getPackageName(), R.layout.widget_countdown);
        rv.setTextViewText(R.id.widget_title, title);

        if (target <= 0L) {
            rv.setTextViewText(R.id.widget_days, "–");
            rv.setTextViewText(R.id.widget_sub, "Open app to set");
        } else {
            long diff = target - System.currentTimeMillis();
            if (diff <= 0L) {
                rv.setTextViewText(R.id.widget_days, "0");
                rv.setTextViewText(R.id.widget_sub, "Finished!");
            } else {
                long days = diff / DAY_MS;
                long hours = (diff % DAY_MS) / HOUR_MS;
                long minutes = (diff % HOUR_MS) / MIN_MS;
                rv.setTextViewText(R.id.widget_days, Long.toString(days));
                rv.setTextViewText(R.id.widget_sub, hours + "h " + minutes + "m left");
            }
        }

        // Tapping the widget opens the app.
        Intent open = new Intent(context, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        rv.setOnClickPendingIntent(R.id.widget_root,
                PendingIntent.getActivity(context, 0, open, piFlags()));
        return rv;
    }

    /** Schedules the next one-minute refresh so the widget stays current. */
    private static void scheduleTick(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.set(AlarmManager.RTC, System.currentTimeMillis() + MIN_MS, tickIntent(context));
    }

    private static void cancelTick(Context context) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am != null) am.cancel(tickIntent(context));
    }

    private static PendingIntent tickIntent(Context context) {
        Intent i = new Intent(context, CountdownWidget.class);
        i.setAction(ACTION_TICK);
        return PendingIntent.getBroadcast(context, 1, i, piFlags());
    }

    private static int piFlags() {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return flags;
    }
}
