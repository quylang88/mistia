package vn.com.quyln.mistia.feature.planning

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.Density
import vn.com.quyln.mistia.core.model.CreditCardNetwork

internal fun planningCreditCardColors(network: CreditCardNetwork): List<Color> = when (network) {
    CreditCardNetwork.VISA -> listOf(Color(0xFF1A5BD7), Color(0xFF1744A7), Color(0xFF0C255F))
    CreditCardNetwork.MASTERCARD -> listOf(Color(0xFFD43C2F), Color(0xFFF2932E), Color(0xFF682A79))
    CreditCardNetwork.JCB -> listOf(Color(0xFF1B78B5), Color(0xFF17985F), Color(0xFFD43C4A))
    CreditCardNetwork.AMERICAN_EXPRESS -> listOf(Color(0xFF2FB7C7), Color(0xFF1B77B6), Color(0xFF164B83))
    CreditCardNetwork.UNION_PAY -> listOf(Color(0xFFC92237), Color(0xFF1968B3), Color(0xFF0C8A5A))
    CreditCardNetwork.OTHER -> listOf(Color(0xFF556270), Color(0xFF4E7A87), Color(0xFF2A3A46))
}

internal fun planningCreditCardNetworkName(network: CreditCardNetwork): String = when (network) {
    CreditCardNetwork.VISA -> "Visa"
    CreditCardNetwork.MASTERCARD -> "Mastercard"
    CreditCardNetwork.JCB -> "JCB"
    CreditCardNetwork.AMERICAN_EXPRESS -> "American Express"
    CreditCardNetwork.UNION_PAY -> "UnionPay"
    CreditCardNetwork.OTHER -> ""
}

@Composable
internal fun PlanningCreditCardNetworkMark(network: CreditCardNetwork, description: String, modifier: Modifier = Modifier) {
    Box(modifier.size(66.dp, 38.dp).semantics { contentDescription = description }, contentAlignment = Alignment.CenterEnd) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, 1f)) {
            Box(Modifier.clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                when (network) {
                    CreditCardNetwork.VISA -> Text("VISA", fontSize = 18.sp, lineHeight = 22.sp, fontWeight = FontWeight.Black, fontStyle = FontStyle.Italic,
                        color = Color(0xFF243D92), modifier = Modifier.background(Color.White, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 6.dp))
                    CreditCardNetwork.MASTERCARD -> Box(Modifier.size(54.dp, 34.dp), contentAlignment = Alignment.Center) {
                        Canvas(Modifier.matchParentSize()) {
                            drawCircle(Color(0xFFEB001B), 15.dp.toPx(), Offset(size.width / 2 - 9.dp.toPx(), size.height / 2))
                            drawCircle(Color(0xFFF79E1B), 15.dp.toPx(), Offset(size.width / 2 + 9.dp.toPx(), size.height / 2))
                        }
                        Text("MC", color = Color.White, fontSize = 9.sp, lineHeight = 11.sp, fontWeight = FontWeight.Black)
                    }
                    CreditCardNetwork.JCB -> Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        listOf("J" to Color(0xFF1B78B5), "C" to Color(0xFF1E9C5F), "B" to Color(0xFFD13C4A)).forEach { (letter, color) ->
                            Box(Modifier.size(16.dp, 28.dp).background(color, RoundedCornerShape(5.dp)), contentAlignment = Alignment.Center) {
                                Text(letter, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.Black, color = Color.White)
                            }
                        }
                    }
                    CreditCardNetwork.AMERICAN_EXPRESS -> Column(Modifier.size(54.dp, 34.dp).background(Color(0xFF2178B8), RoundedCornerShape(7.dp))
                        .border(1.dp, Color.White.copy(alpha = .72f), RoundedCornerShape(7.dp)),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Text("AMEX", color = Color.White, fontSize = 13.sp, lineHeight = 14.sp, fontWeight = FontWeight.Black)
                        Text("CARD", color = Color.White, fontSize = 7.sp, lineHeight = 8.sp, fontWeight = FontWeight.Black)
                    }
                    CreditCardNetwork.UNION_PAY -> Box(Modifier.size(52.dp, 31.dp), contentAlignment = Alignment.Center) {
                        Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.spacedBy((-4).dp)) {
                            listOf(Color(0xFFD61F35), Color(0xFF1B68B3), Color(0xFF0E8A56)).forEach { color ->
                                Box(Modifier.weight(1f).fillMaxHeight().background(color, RoundedCornerShape(5.dp)))
                            }
                        }
                        Text("UP", fontSize = 11.sp, lineHeight = 13.sp, color = Color.White, fontWeight = FontWeight.Black)
                    }
                    CreditCardNetwork.OTHER -> Box(Modifier.size(54.dp, 34.dp).background(Color.White.copy(alpha = .16f), RoundedCornerShape(9.dp)),
                        contentAlignment = Alignment.Center) { Icon(Icons.Default.CreditCard, null, tint = Color.White, modifier = Modifier.size(24.dp)) }
                }
            }
        }
    }
}
