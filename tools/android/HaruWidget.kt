package com.isla0x.haruring

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** 홈 화면 "오늘" 위젯 (PRO). 오늘 할 일과 루틴을 보여주고, 눌러서 완료 표시를 바꿔요. */
class HaruWidget : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE = "com.isla0x.haruring.TOGGLE"
        private const val ROWS = 5

        fun refresh(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, HaruWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, build(ctx))
        }

        private fun dayKey(c: Calendar) =
            String.format("%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))

        private fun isPro(pro: JSONObject?): Boolean {
            if (pro == null) return false
            if (pro.optBoolean("purchased")) return true
            val end = pro.optLong("trialEnd", 0L)
            return end > System.currentTimeMillis()
        }

        private fun isDone(o: JSONObject, day: String): Boolean {
            if (o.optBoolean("isRoutine")) {
                val a = o.optJSONArray("doneDates") ?: return false
                for (i in 0 until a.length()) if (a.optString(i) == day) return true
                return false
            }
            return o.optBoolean("done")
        }

        private fun startDay(o: JSONObject): String? {
            var start: String? = if (o.isNull("created")) null else o.optString("created")
            val a = o.optJSONArray("doneDates")
            if (a != null) for (i in 0 until a.length()) {
                val d = a.optString(i)
                if (start == null || d < start) start = d
            }
            return start
        }

        /** 앱의 scheduledOn과 같은 규칙: 오늘 나타나는 항목인지 */
        private fun scheduledToday(o: JSONObject, today: String): Boolean {
            if (!o.optBoolean("isRoutine")) return !o.isNull("date") && o.optString("date") == today
            return true
        }

        private fun open(ctx: Context, link: String?, req: Int): PendingIntent {
            val i = Intent(ctx, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (link != null) i.putExtra("haruLink", link)
            return PendingIntent.getActivity(ctx, req, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        fun build(ctx: Context): RemoteViews {
            val v = RemoteViews(ctx.packageName, R.layout.haru_widget)
            val prefs = ctx.getSharedPreferences(HaruNative.PREFS, Context.MODE_PRIVATE)
            val now = Calendar.getInstance()
            val today = dayKey(now)
            val pro = try { JSONObject(prefs.getString("pro_v1", "") ?: "") } catch (e: Exception) { null }

            val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3, R.id.row4)
            val markIds = intArrayOf(R.id.mark0, R.id.mark1, R.id.mark2, R.id.mark3, R.id.mark4)
            val titleIds = intArrayOf(R.id.title0, R.id.title1, R.id.title2, R.id.title3, R.id.title4)
            for (r in rowIds) v.setViewVisibility(r, android.view.View.GONE)
            v.setViewVisibility(R.id.more, android.view.View.GONE)
            v.setViewVisibility(R.id.msg, android.view.View.GONE)

            val head = "오늘 · ${now.get(Calendar.MONTH) + 1}월 ${now.get(Calendar.DAY_OF_MONTH)}일"

            if (!isPro(pro)) {
                v.setTextViewText(R.id.head, head)
                v.setTextViewText(R.id.msg, "PRO에서 쓸 수 있는 위젯이에요\n눌러서 하루링 PRO 열기")
                v.setViewVisibility(R.id.msg, android.view.View.VISIBLE)
                v.setOnClickPendingIntent(R.id.root, open(ctx, "haruring://pro", 1))
                return v
            }

            // 오늘 항목 모으기 (시간 있는 것 → 시간 없는 루틴 → 시간 없는 할 일)
            val list = ArrayList<JSONObject>()
            try {
                val arr = JSONArray(prefs.getString("items_v1", "[]") ?: "[]")
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    if (scheduledToday(o, today)) list.add(o)
                }
            } catch (e: Exception) { }
            fun rank(o: JSONObject): Int {
                val timed = !o.isNull("time") && o.optString("time").isNotEmpty()
                return if (timed) 0 else if (o.optBoolean("isRoutine")) 1 else 2
            }
            list.sortWith(compareBy<JSONObject>({ rank(it) }, { if (rank(it) == 0) o2t(it) else "" }))

            val doneCount = list.count { isDone(it, today) }
            v.setTextViewText(R.id.head, "$head  ·  $doneCount/${list.size}")
            v.setOnClickPendingIntent(R.id.root, open(ctx, null, 2))

            if (list.isEmpty()) {
                v.setTextViewText(R.id.msg, "오늘은 할 일이 없어요")
                v.setViewVisibility(R.id.msg, android.view.View.VISIBLE)
            }
            for ((n, o) in list.take(ROWS).withIndex()) {
                val done = isDone(o, today)
                val time = if (o.isNull("time")) "" else o.optString("time")
                v.setViewVisibility(rowIds[n], android.view.View.VISIBLE)
                v.setTextViewText(markIds[n], if (done) "●" else "○")
                v.setTextColor(markIds[n], if (done) Color.parseColor("#5B9BF7") else Color.parseColor("#B8C0CC"))
                v.setTextViewText(titleIds[n], if (time.isNotEmpty()) "$time  ${o.optString("title")}" else o.optString("title"))
                v.setTextColor(titleIds[n], if (done) Color.parseColor("#9AA3B2") else Color.parseColor("#1F2937"))
                val t = Intent(ctx, HaruWidget::class.java).setAction(ACTION_TOGGLE)
                    .putExtra("id", o.optString("id")).putExtra("day", today).putExtra("done", !done)
                val pi = PendingIntent.getBroadcast(
                    ctx, 100 + n, t, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                v.setOnClickPendingIntent(rowIds[n], pi)
            }
            if (list.size > ROWS) {
                v.setTextViewText(R.id.more, "외 ${list.size - ROWS}개")
                v.setViewVisibility(R.id.more, android.view.View.VISIBLE)
            }
            return v
        }

        private fun o2t(o: JSONObject): String = o.optString("time")
    }

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) mgr.updateAppWidget(id, build(ctx))
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        super.onReceive(ctx, intent)
        if (intent.action != ACTION_TOGGLE) return
        val id = intent.getStringExtra("id") ?: return
        val day = intent.getStringExtra("day") ?: return
        val done = intent.getBooleanExtra("done", false)
        val prefs = ctx.getSharedPreferences(HaruNative.PREFS, Context.MODE_PRIVATE)
        // 앱이 열릴 때 가져갈 체크 기록
        try {
            val t = JSONArray(prefs.getString("toggles_v1", "[]") ?: "[]")
            t.put(JSONObject().put("id", id).put("day", day).put("done", done))
            prefs.edit().putString("toggles_v1", t.toString()).apply()
        } catch (e: Exception) { }
        // 위젯 화면에도 바로 반영
        try {
            val arr = JSONArray(prefs.getString("items_v1", "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                if (o.optString("id") != id) continue
                if (o.optBoolean("isRoutine")) {
                    val old = o.optJSONArray("doneDates") ?: JSONArray()
                    val next = JSONArray()
                    for (k in 0 until old.length()) if (old.optString(k) != day) next.put(old.optString(k))
                    if (done) next.put(day)
                    o.put("doneDates", next)
                } else {
                    o.put("done", done)
                }
            }
            prefs.edit().putString("items_v1", arr.toString()).apply()
        } catch (e: Exception) { }
        refresh(ctx)
    }
}
