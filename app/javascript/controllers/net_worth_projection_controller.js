import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Manages net worth projection display including timeframe selection,
// scenario toggling, and D3.js chart rendering
export default class extends Controller {
  static targets = [
    "content",
    "toggleButton",
    "chevronIcon",
    "timeframeCheckbox",
    "scenarioCheckbox",
    "chartContainer",
    "milestones",
    "loadingIndicator",
    "insufficientDataWarning",
    "qualityWarning",
    "qualityWarningText"
  ]

  static values = {
    canProject: Boolean
  }

  connect() {
    this.expanded = false
    this.projectionData = null

    // Chart configuration
    this.chartConfig = {
      margin: { top: 20, right: 20, bottom: 30, left: 60 },
      colors: {
        conservative: "#f97316", // orange
        realistic: "#3b82f6", // blue
        optimistic: "#10b981" // green
      },
      lineStyles: {
        historical: "solid",
        projection: "dashed"
      }
    }
  }

  toggleExpanded() {
    this.expanded = !this.expanded

    if (this.expanded) {
      this.contentTarget.classList.remove("hidden")
      this.chevronIconTarget.style.transform = "rotate(180deg)"

      // Load projection data if not already loaded
      if (!this.projectionData) {
        this.loadProjections()
      }
    } else {
      this.contentTarget.classList.add("hidden")
      this.chevronIconTarget.style.transform = "rotate(0deg)"
    }
  }

  updateTimeframes() {
    if (this.projectionData) {
      this.loadProjections()
    }
  }

  updateScenarios() {
    if (this.projectionData) {
      this.renderChart()
      this.renderMilestones()
    }
  }

  async loadProjections() {
    // Show loading state
    this.showLoading()

    // Get selected timeframes
    const timeframes = this.getSelectedTimeframes()

    if (timeframes.length === 0) {
      this.hideLoading()
      return
    }

    try {
      const response = await fetch(`/net_worth_projections.json?timeframes=${timeframes.join(',')}`)

      if (!response.ok) {
        const error = await response.json()
        if (error.error === "insufficient_data") {
          this.showInsufficientDataWarning()
        }
        this.hideLoading()
        return
      }

      this.projectionData = await response.json()

      // Show quality warning if present
      if (this.projectionData.data_quality?.warning) {
        this.showQualityWarning(this.projectionData.data_quality.warning)
      }

      this.renderChart()
      this.renderMilestones()
      this.hideLoading()
    } catch (error) {
      console.error("Failed to load projections:", error)
      this.hideLoading()
    }
  }

  getSelectedTimeframes() {
    return Array.from(this.timeframeCheckboxTargets)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => parseInt(checkbox.value))
  }

  getSelectedScenarios() {
    return Array.from(this.scenarioCheckboxTargets)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)
  }

  renderChart() {
    const container = this.chartContainerTarget
    const selectedScenarios = this.getSelectedScenarios()

    // Clear existing chart
    d3.select(container).selectAll("*").remove()

    if (!this.projectionData || selectedScenarios.length === 0) {
      return
    }

    // Setup dimensions
    const containerRect = container.getBoundingClientRect()
    const width = containerRect.width
    const height = containerRect.height
    const { margin } = this.chartConfig

    const chartWidth = width - margin.left - margin.right
    const chartHeight = height - margin.top - margin.bottom

    // Create SVG
    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Prepare data
    const allValues = []
    const currentDate = new Date()

    selectedScenarios.forEach(scenarioName => {
      const scenario = this.projectionData.scenarios[scenarioName]
      scenario.values.forEach(point => {
        allValues.push({
          date: new Date(point.date),
          value: parseFloat(point.value.amount),
          scenario: scenarioName
        })
      })
    })

    // Scales
    const xScale = d3.scaleTime()
      .domain(d3.extent(allValues, d => d.date))
      .range([0, chartWidth])

    const yScale = d3.scaleLinear()
      .domain([
        d3.min(allValues, d => d.value) * 0.95,
        d3.max(allValues, d => d.value) * 1.05
      ])
      .range([chartHeight, 0])

    // Axes
    svg.append("g")
      .attr("transform", `translate(0,${chartHeight})`)
      .call(d3.axisBottom(xScale).ticks(6))
      .selectAll("text")
      .style("fill", "var(--color-text-primary)")

    svg.append("g")
      .call(d3.axisLeft(yScale).ticks(6).tickFormat(d => this.formatCurrency(d)))
      .selectAll("text")
      .style("fill", "var(--color-text-primary)")

    // Line generator
    const line = d3.line()
      .x(d => xScale(d.date))
      .y(d => yScale(d.value))

    // Draw lines for each scenario
    selectedScenarios.forEach(scenarioName => {
      const scenarioData = allValues.filter(d => d.scenario === scenarioName)

      svg.append("path")
        .datum(scenarioData)
        .attr("fill", "none")
        .attr("stroke", this.chartConfig.colors[scenarioName])
        .attr("stroke-width", 2)
        .attr("stroke-dasharray", "5,5")
        .attr("d", line)
    })

    // Add vertical line at current date
    svg.append("line")
      .attr("x1", xScale(currentDate))
      .attr("x2", xScale(currentDate))
      .attr("y1", 0)
      .attr("y2", chartHeight)
      .attr("stroke", "var(--color-border-primary)")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "3,3")

    // Add "Today" label
    svg.append("text")
      .attr("x", xScale(currentDate))
      .attr("y", -5)
      .attr("text-anchor", "middle")
      .attr("font-size", "12px")
      .attr("fill", "var(--color-text-subdued)")
      .text("Today")
  }

  renderMilestones() {
    const container = this.milestonesTarget
    const selectedScenarios = this.getSelectedScenarios()
    const timeframes = this.getSelectedTimeframes()

    // Clear existing
    container.innerHTML = ""

    if (!this.projectionData || selectedScenarios.length === 0) {
      return
    }

    // Show milestone for longest timeframe only
    const maxTimeframe = Math.max(...timeframes)

    selectedScenarios.forEach(scenarioName => {
      const scenario = this.projectionData.scenarios[scenarioName]
      const milestone = scenario.milestones[maxTimeframe]

      if (!milestone) return

      const card = document.createElement("div")
      card.className = "bg-gray-50 rounded-lg p-3"
      card.innerHTML = `
        <div class="text-xs font-medium text-subdued mb-1">
          ${this.formatScenarioName(scenarioName)} (${maxTimeframe}yr)
        </div>
        <div class="text-lg font-bold" style="color: ${this.chartConfig.colors[scenarioName]}">
          ${milestone.value.formatted}
        </div>
        <div class="text-xs text-subdued mt-1">
          ${milestone.growth_from_current.formatted} growth
        </div>
      `

      container.appendChild(card)
    })
  }

  formatCurrency(value) {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(value)
  }

  formatScenarioName(scenario) {
    return scenario.charAt(0).toUpperCase() + scenario.slice(1)
  }

  showLoading() {
    this.loadingIndicatorTarget.classList.remove("hidden")
    this.chartContainerTarget.classList.add("hidden")
  }

  hideLoading() {
    this.loadingIndicatorTarget.classList.add("hidden")
    this.chartContainerTarget.classList.remove("hidden")
  }

  showInsufficientDataWarning() {
    this.insufficientDataWarningTarget.classList.remove("hidden")
    this.chartContainerTarget.classList.add("hidden")
  }

  showQualityWarning(message) {
    this.qualityWarningTextTarget.textContent = message
    this.qualityWarningTarget.classList.remove("hidden")
  }
}
