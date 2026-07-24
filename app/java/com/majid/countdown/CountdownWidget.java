package com.majid.countdown;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.widget.RemoteViews;

/**
 * Home-screen widget. Each instance renders its bound countdown into a bitmap
 * with the very same {@link CountdownRenderer} the app uses, then refreshes
 * about once a minute so the numbers stay current.
 */
public class CountdownWidget extends AppWidgetProvider {

    public static final String ACTION_TICK = "com.majid.countdown.ACTION_TICK";
    private static final long MIN_MS = 60000L;

    @Override
    public void onUpdate(Context ctx, AppWidgetManager mgr, int[] ids) {
        for (int i = 0; i < ids.length; i++) render(ctx, mgr, ids[i]);
        scheduleTick(ctx);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context ctx, AppWidgetManager mgr,
                                          int id, Bundle newOptions) {
        render(ctx, mgr, id);
    }

    @Override
    public void onEnabled(Context ctx) {
        scheduleTick(ctx);
    }

    @Override
    public void onDisabled(Context ctx) {
        cancelTick(ctx);
    }

    @Override
    public void onDeleted(Context ctx, int[] ids) {
        Store s = new Store(ctx);
        for (int i = 0; i < ids.length; i++) s.unbindWidget(ids[i]);
    }

    @Override
    public void onReceive(Context ctx, Intent intent) {
        super.onReceive(ctx, intent);
        if (intent != null && ACTION_TICK.equals(intent.getAction())) {
            updateAll(ctx);
            scheduleTick(ctx);
        }
    }

    /** Re-render every placed widget (called by the app after edits). */
    public static void updateAll(Context ctx) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        int[] ids = mgr.getAppWidgetIds(new ComponentName(ctx, CountdownWidget.class));
        for (int i = 0; i < ids.length; i++) render(ctx, mgr, ids[i]);
    }

    private static void render(Context ctx, AppWidgetManager mgr, int id) {
        int[] size = widgetSizePx(ctx, mgr, id);
        Bitmap bmp = Bitmap.createBitmap(size[0], size[1], Bitmap.Config.ARGB_8888);
        Canvas cv = new Canvas(bmp);

        Store store = new Store(ctx);
        Countdown c = store.forWidget(id);
        if (c == null) {
            drawPlaceholder(cv, size[0], size[1]);
        } else {
            CountdownRenderer.draw(cv, size[0], size[1], c.style, c.colorIndex,
                    c.title, c.remainingMs(), c.totalMs(), 0L, true);
        }

        RemoteViews rv = new RemoteViews(ctx.getPackageName(), R.layout.widget_countdown);
        rv.setImageViewBitmap(R.id.widget_image, bmp);

        Intent open = new Intent(ctx, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        rv.setOnClickPendingIntent(R.id.widget_image,
                PendingIntent.getActivity(ctx, 0, open, piFlags()));

        mgr.updateAppWidget(id, rv);
    }

    private static void drawPlaceholder(Canvas c, int w, int h) {
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(0xFF7C4DFF);
        float r = h * 0.13f;
        c.drawRoundRect(new RectF(0, 0, w, h), r, r, p);
        p.setColor(0xFFFFFFFF);
        p.setTextSize(h * 0.13f);
        p.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        p.setTextAlign(Paint.Align.CENTER);
        c.drawText("Countdown", w / 2f, h * 0.45f, p);
        p.setTextSize(h * 0.09f);
        p.setAlpha(200);
        c.drawText("Tap to set up", w / 2f, h * 0.62f, p);
    }

    private static int[] widgetSizePx(Context ctx, AppWidgetManager mgr, int id) {
        DisplayMetrics dm = ctx.getResources().getDisplayMetrics();
        int wDp = 250, hDp = 150;
        try {
            Bundle o = mgr.getAppWidgetOptions(id);
            if (o != null) {
                int mw = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0);
                int mh = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0);
                if (mw > 0) wDp = mw;
                if (mh > 0) hDp = mh;
            }
        } catch (Exception ignored) {
        }
        // Cap the bitmap so the RemoteViews stays well under Android's
        // per-widget bitmap memory limit (transparent corners need ARGB_8888).
        int wPx = Math.max(120, Math.min(560, Math.round(wDp * dm.density)));
        int hPx = Math.max(90, Math.min(360, Math.round(hDp * dm.density)));
        return new int[]{wPx, hPx};
    }

    private static void scheduleTick(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am != null) am.set(AlarmManager.RTC, System.currentTimeMillis() + MIN_MS, tickIntent(ctx));
    }

    private static void cancelTick(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am != null) am.cancel(tickIntent(ctx));
    }

    private static PendingIntent tickIntent(Context ctx) {
        Intent i = new Intent(ctx, CountdownWidget.class);
        i.setAction(ACTION_TICK);
        return PendingIntent.getBroadcast(ctx, 1, i, piFlags());
    }

    private static int piFlags() {
        int f = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) f |= PendingIntent.FLAG_IMMUTABLE;
        return f;
    }
}
