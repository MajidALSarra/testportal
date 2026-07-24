package com.majid.countdown;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Persists the list of countdowns and the widget -> countdown mapping. */
public class Store {

    private static final String PREFS = "countdown_store";
    private static final String KEY_ITEMS = "items";
    private static final String KEY_WIDGET_PREFIX = "widget_";

    private final SharedPreferences sp;

    public Store(Context ctx) {
        sp = ctx.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** All countdowns, soonest target first. */
    public List<Countdown> all() {
        List<Countdown> out = new ArrayList<Countdown>();
        try {
            JSONArray arr = new JSONArray(sp.getString(KEY_ITEMS, "[]"));
            for (int i = 0; i < arr.length(); i++) {
                out.add(Countdown.fromJson(arr.getJSONObject(i)));
            }
        } catch (Exception ignored) {
        }
        Collections.sort(out, new Comparator<Countdown>() {
            @Override
            public int compare(Countdown a, Countdown b) {
                return Long.compare(a.target, b.target);
            }
        });
        return out;
    }

    public Countdown get(long id) {
        List<Countdown> list = all();
        for (int i = 0; i < list.size(); i++) {
            if (list.get(i).id == id) return list.get(i);
        }
        return null;
    }

    /** Inserts or updates a countdown by id. */
    public void put(Countdown c) {
        List<Countdown> list = all();
        boolean replaced = false;
        for (int i = 0; i < list.size(); i++) {
            if (list.get(i).id == c.id) {
                list.set(i, c);
                replaced = true;
                break;
            }
        }
        if (!replaced) list.add(c);
        save(list);
    }

    public void delete(long id) {
        List<Countdown> list = all();
        for (int i = list.size() - 1; i >= 0; i--) {
            if (list.get(i).id == id) list.remove(i);
        }
        save(list);
    }

    private void save(List<Countdown> list) {
        JSONArray arr = new JSONArray();
        try {
            for (int i = 0; i < list.size(); i++) {
                arr.put(list.get(i).toJson());
            }
        } catch (Exception ignored) {
        }
        sp.edit().putString(KEY_ITEMS, arr.toString()).apply();
    }

    // ---- widget -> countdown mapping ----

    public void bindWidget(int widgetId, long countdownId) {
        sp.edit().putLong(KEY_WIDGET_PREFIX + widgetId, countdownId).apply();
    }

    public long widgetCountdownId(int widgetId) {
        return sp.getLong(KEY_WIDGET_PREFIX + widgetId, -1L);
    }

    public void unbindWidget(int widgetId) {
        sp.edit().remove(KEY_WIDGET_PREFIX + widgetId).apply();
    }

    /** The countdown a widget shows: its bound one, else the soonest upcoming. */
    public Countdown forWidget(int widgetId) {
        long id = widgetCountdownId(widgetId);
        if (id != -1L) {
            Countdown c = get(id);
            if (c != null) return c;
        }
        List<Countdown> list = all();
        return list.isEmpty() ? null : list.get(0);
    }
}
