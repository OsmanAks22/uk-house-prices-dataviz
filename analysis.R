# Setup: load packages, read and rebase data to 1995 = 100
library(tidyverse); library(scales); library(ggtext); library(patchwork)
dir.create("output", showWarnings = FALSE)
hpi <- read_csv("data/hpi_clean.csv") |> mutate(Date = as.Date(Date))
hpi <- hpi |> arrange(RegionName, Date) |> group_by(RegionName) |>
  mutate(Index95 = Index / Index[Date == min(Date)] * 100) |> ungroup()
theme_story <- theme_minimal(base_size = 12) +
  theme(plot.title = element_markdown(face = "bold", size = 14),
        plot.subtitle = element_text(colour = "grey40"),
        plot.caption = element_text(colour = "grey55", size = 8),
        panel.grid.minor = element_blank(), legend.position = "none")
col_london <- "#C8102E"; col_north <- "#0072B2"; col_grey <- "grey80"

# Viz 1: regional index since 1995, London highlighted
p1 <- hpi |> ggplot(aes(Date, Index95, group = RegionName)) +
  geom_line(colour = col_grey, linewidth = 0.5) +
  geom_line(data = ~filter(.x, RegionName == "North West"), colour = col_north, linewidth = 1.1) +
  geom_line(data = ~filter(.x, RegionName == "London"), colour = col_london, linewidth = 1.1) +
  annotate("text", x = as.Date("2010-01-01"), y = 480, label = "London", colour = col_london, size = 4, fontface = "bold") +
  annotate("text", x = as.Date("2015-01-01"), y = 220, label = "North West", colour = col_north, size = 3.5, fontface = "bold") +
  labs(title = "<span style='color:#C8102E'>London</span> outpaced every English region for two decades",
       subtitle = "Regional house price index, January 1995 = 100. Grey: England, South East, North East",
       x = NULL, y = "Index (1995 = 100)", caption = "Source: HM Land Registry UK House Price Index") + theme_story
ggsave("output/viz1_long_race.png", p1, width = 9, height = 5.5, dpi = 300)

# Viz 2: cumulative 10-year growth by region (dumbbell)
latest <- max(hpi$Date)
growth10 <- hpi |> filter(Date %in% c(latest %m-% years(10), latest)) |> group_by(RegionName) |>
  summarise(Start = first(AveragePrice), End = last(AveragePrice), .groups = "drop") |>
  mutate(Growth = End / Start - 1, RegionName = fct_reorder(RegionName, Growth))
p2 <- growth10 |> ggplot(aes(y = RegionName)) +
  geom_segment(aes(x = 0, xend = Growth, yend = RegionName), colour = col_grey, linewidth = 3) +
  geom_point(aes(x = Growth, colour = RegionName == "London"), size = 4) +
  geom_text(aes(x = Growth, label = percent(Growth, accuracy = 1)), hjust = -0.4, size = 3.2) +
  scale_colour_manual(values = c(`TRUE` = col_london, `FALSE` = col_north)) +
  scale_x_continuous(labels = percent, expand = expansion(mult = c(0.02, 0.15))) +
  labs(title = "Over the past decade, <span style='color:#C8102E'>London</span> recorded the weakest growth",
       subtitle = paste0("Cumulative house price growth by region, ", year(latest) - 10, "\u2013", year(latest)),
       x = "10-year price growth", y = NULL, caption = "Source: HM Land Registry UK House Price Index") + theme_story
ggsave("output/viz2_catchup.png", p2, width = 9, height = 5.5, dpi = 300)

# Viz 3: London price index by property type (detached vs flats)
london_types <- hpi |> filter(RegionName == "London", !is.na(DetachedIndex), !is.na(FlatIndex)) |>
  select(Date, DetachedIndex, FlatIndex) |> pivot_longer(-Date, names_to = "Type", values_to = "Idx")
p3 <- london_types |> ggplot(aes(Date, Idx, colour = Type)) + geom_line(linewidth = 1) +
  scale_colour_manual(values = c(DetachedIndex = col_london, FlatIndex = col_north), labels = c("Detached houses", "Flats")) +
  labs(title = "In London, <span style='color:#C8102E'>detached houses</span> have outgrown flats since 2016",
       subtitle = "London price index by property type, January 2023 = 100 (the UK HPI base)",
       x = NULL, y = "Index (Jan 2023 = 100)", caption = "Source: HM Land Registry UK House Price Index") +
  theme_story + theme(legend.position = "right", legend.title = element_blank())
ggsave("output/viz3_property_types.png", p3, width = 9, height = 5.5, dpi = 300)

# Viz 4: London monthly sales, 12-month moving average
roll_mean <- function(x, k = 12) { n <- length(x); out <- rep(NA_real_, n); for (i in k:n) out[i] <- mean(x[(i - k + 1):i]); out }
london_vol <- hpi |> filter(RegionName == "London", !is.na(SalesVolume)) |> arrange(Date) |> mutate(VolMA = roll_mean(SalesVolume, 12))
p4 <- london_vol |> ggplot(aes(Date, VolMA)) +
  geom_area(fill = col_london, alpha = 0.15) + geom_line(colour = col_london, linewidth = 0.9) +
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale()), limits = c(0, NA)) +
  labs(title = "Transaction volumes never recovered after the <span style='color:#C8102E'>2008 crisis</span>",
       subtitle = "Monthly residential sales in London, 12-month moving average",
       x = NULL, y = "Sales per month", caption = "Source: HM Land Registry UK House Price Index") + theme_story
ggsave("output/viz4_volume.png", p4, width = 9, height = 5.5, dpi = 300)

# Viz 5: year-on-year growth heatmap by region and year
# YoY is the 12-month change on the monthly series, read at December (and at the latest month
# for the final, partial year). Lagging the filtered December rows instead would make the
# final tile a December-to-latest-month change, not a year-on-year one.
heat <- hpi |> arrange(RegionName, Date) |> group_by(RegionName) |>
  mutate(YoY = Index / lag(Index, 12) - 1) |> ungroup() |>
  mutate(Year = year(Date), Month = month(Date)) |>
  filter(Month == 12 | (Year == max(Year) & Month == max(Month[Year == max(Year)]))) |>
  filter(!is.na(YoY), Year >= 2005) |>
  mutate(RegionName = factor(RegionName, levels = c("London", "South East", "England", "North West", "North East")))
p5 <- heat |> ggplot(aes(Year, RegionName, fill = YoY)) + geom_tile(colour = "white", linewidth = 0.5) +
  scale_fill_gradient2(low = col_london, mid = "grey95", high = col_north, midpoint = 0, labels = percent) +
  scale_x_continuous(breaks = seq(2006, 2026, 4), expand = c(0, 0)) +
  labs(title = "Annual price growth shows synchronised <span style='color:#0072B2'>booms</span> and <span style='color:#C8102E'>downturns</span>",
       subtitle = "Year-on-year house price change (%). Red indicates falling prices",
       x = NULL, y = NULL, fill = NULL, caption = "Source: HM Land Registry UK House Price Index") +
  theme_story + theme(legend.position = "right", panel.grid = element_blank())
ggsave("output/viz5_heatmap.png", p5, width = 9, height = 5.5, dpi = 300)

# Viz 6: value today of £100,000 invested in a 1995 home, by region
final <- hpi |> group_by(RegionName) |> summarise(Multiple = last(Index95) / 100, .groups = "drop") |>
  mutate(Value = 100000 * Multiple, RegionName = fct_reorder(RegionName, Value))
p6 <- final |> ggplot(aes(Value, RegionName)) + geom_col(aes(fill = RegionName == "London"), width = 0.7) +
  geom_text(aes(label = label_currency(prefix = "\u00a3", accuracy = 1, scale_cut = cut_short_scale())(Value)), hjust = -0.1, size = 3.4) +
  scale_fill_manual(values = c(`TRUE` = col_london, `FALSE` = col_north)) +
  scale_x_continuous(labels = label_currency(prefix = "\u00a3", scale_cut = cut_short_scale()), expand = expansion(mult = c(0, 0.18))) +
  labs(title = "\u00a3100,000 invested in an average 1995 home, valued today",
       subtitle = "Nominal value by region \u2013 London retains the highest absolute value",
       x = NULL, y = NULL, caption = "Source: HM Land Registry UK House Price Index") + theme_story
ggsave("output/viz6_infographic.png", p6, width = 9, height = 5.5, dpi = 300)
