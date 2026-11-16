import { Controller } from "@hotwired/stimulus"
import { compare } from "compare-versions"
import { AppDock } from "../appdock"

const PROJECT_URL = "https://github.com/wjd-jax/appdock"
const VERSION_URL = "https://api.github.com/repos/wjd-jax/appdock/releases/latest"

export default class extends Controller {
  static values = { version: String, title: String }
  static targets = ["newVersion"]

  connect() {
    if (AppDock.isDevelopment()) {
      this.render(this.titleValue, PROJECT_URL)
    } else {
      this.check()
    }
  }

  check() {
    fetch(VERSION_URL, {
      headers: {
        "Accept": "application/vnd.github.v3+json"
      }
    }).then((response) => response.json())
      .then((json) => {
        const releaseVersion = json.tag_name
        if (!releaseVersion) { return }
        if (compare(releaseVersion, this.versionValue, "<=")) { return }
        const releaseLink = json.html_url
        const title = this.titleValue + " " + releaseVersion
        this.render(title, releaseLink)
    });
  }

  render(title, link) {
    this.newVersionTarget.innerHTML = "<a target='_blank' href='" + link + "'>" +
      "<i class='fas fa-rainbow'></i>" + title + "</a>"
  }
}
