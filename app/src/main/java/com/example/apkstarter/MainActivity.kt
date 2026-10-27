package com.example.apkstarter

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setBackgroundColor(Color.rgb(245, 248, 252))
        }

        val heading = TextView(this).apply {
            text = "Приложение собрано!"
            textSize = 26f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(22, 36, 58))
        }

        val message = TextView(this).apply {
            text = "Этот APK собран на GitHub Actions, без компьютера и VPS."
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(75, 89, 109))
        }

        val button = Button(this).apply {
            text = "Проверить кнопку"
            setOnClickListener {
                message.text = "Всё работает! Теперь можно создавать свои приложения."
            }
        }

        container.addView(heading, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
        container.addView(message, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(20) })
        container.addView(button, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(22) })

        setContentView(container)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()
}
