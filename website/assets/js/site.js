(() => {
  const banner = document.querySelector("[data-ios-banner]");
  const closeButton = document.querySelector("[data-banner-close]");
  const dismissedKey = "moontake-ios-banner-dismissed";
  const langSwitches = document.querySelectorAll(".lang-switch");
  const zoomableImages = document.querySelectorAll(".image-card img, .result-card img");
  const isFileProtocol = window.location.protocol === "file:";

  if (isFileProtocol) {
    const marker = "/website/";
    const pathname = window.location.pathname;
    const markerIndex = pathname.indexOf(marker);
    const siteRoot = markerIndex >= 0
      ? pathname.slice(0, markerIndex + "/website".length)
      : pathname.replace(/\/[^/]*$/, "");

    document.querySelectorAll('a[href^="/"]').forEach((link) => {
      const href = link.getAttribute("href");
      if (!href) {
        return;
      }
      link.href = `file://${siteRoot}${href}`;
    });
  }

  const userAgent = navigator.userAgent || "";
  const isIPhone = /iPhone/i.test(userAgent);
  const isSafari = /Safari/i.test(userAgent) && !/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent);
  const isStandalone = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;

  if (banner && isIPhone && isSafari && !isStandalone && !window.localStorage.getItem(dismissedKey)) {
    banner.hidden = false;
    document.body.classList.add("has-ios-banner");
  }

  closeButton?.addEventListener("click", () => {
    if (!banner) {
      return;
    }
    banner.hidden = true;
    document.body.classList.remove("has-ios-banner");
    window.localStorage.setItem(dismissedKey, "1");
  });

  langSwitches.forEach((root, index) => {
    const links = Array.from(root.querySelectorAll("a"));
    if (links.length === 0) {
      return;
    }

    const current = root.querySelector('a[aria-current="page"]') || links[0];
    const menuId = `lang-menu-${index + 1}`;
    const items = links
      .map((link) => {
        const currentAttr = link === current ? ' aria-current="page"' : "";
        return `<a href="${link.href}"${currentAttr}>${link.textContent?.trim() || ""}</a>`;
      })
      .join("");

    root.innerHTML = `
      <button class="lang-toggle" type="button" aria-haspopup="true" aria-expanded="false" aria-controls="${menuId}">
        <span class="lang-toggle__label">${current.textContent?.trim() || "Language"}</span>
        <span class="lang-toggle__chevron" aria-hidden="true">▾</span>
      </button>
      <div class="lang-menu" id="${menuId}" hidden>
        ${items}
      </div>
    `;

    root.classList.add("lang-switch--ready");

    const button = root.querySelector(".lang-toggle");
    const menu = root.querySelector(".lang-menu");

    if (!button || !menu) {
      return;
    }

    const closeMenu = () => {
      root.classList.remove("is-open");
      button.setAttribute("aria-expanded", "false");
      menu.hidden = true;
    };

    const openMenu = () => {
      root.classList.add("is-open");
      button.setAttribute("aria-expanded", "true");
      menu.hidden = false;
    };

    button.addEventListener("click", () => {
      if (root.classList.contains("is-open")) {
        closeMenu();
      } else {
        document.querySelectorAll(".lang-switch.is-open").forEach((node) => {
          node.classList.remove("is-open");
          const nodeButton = node.querySelector(".lang-toggle");
          const nodeMenu = node.querySelector(".lang-menu");
          if (nodeButton) {
            nodeButton.setAttribute("aria-expanded", "false");
          }
          if (nodeMenu) {
            nodeMenu.hidden = true;
          }
        });
        openMenu();
      }
    });

    document.addEventListener("click", (event) => {
      if (!root.contains(event.target)) {
        closeMenu();
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeMenu();
      }
    });
  });

  const lightbox = document.createElement("div");
  lightbox.className = "lightbox";
  lightbox.hidden = true;
  lightbox.innerHTML = `
    <button class="lightbox__close" type="button" aria-label="Close image viewer">&times;</button>
    <div class="lightbox__frame">
      <img class="lightbox__image" alt="">
      <p class="lightbox__caption" hidden></p>
    </div>
  `;
  document.body.appendChild(lightbox);

  const lightboxImage = lightbox.querySelector(".lightbox__image");
  const lightboxCaption = lightbox.querySelector(".lightbox__caption");
  const lightboxClose = lightbox.querySelector(".lightbox__close");

  const closeLightbox = () => {
    lightbox.hidden = true;
    document.body.classList.remove("has-lightbox");
    if (lightboxImage) {
      lightboxImage.removeAttribute("src");
      lightboxImage.alt = "";
    }
    if (lightboxCaption) {
      lightboxCaption.textContent = "";
      lightboxCaption.hidden = true;
    }
  };

  const openLightbox = (image) => {
    if (!(image instanceof HTMLImageElement) || !lightboxImage) {
      return;
    }
    lightboxImage.src = image.currentSrc || image.src;
    lightboxImage.alt = image.alt || "";
    if (lightboxCaption) {
      if (image.alt) {
        lightboxCaption.textContent = image.alt;
        lightboxCaption.hidden = false;
      } else {
        lightboxCaption.textContent = "";
        lightboxCaption.hidden = true;
      }
    }
    lightbox.hidden = false;
    document.body.classList.add("has-lightbox");
  };

  lightboxClose?.addEventListener("click", closeLightbox);
  lightbox.addEventListener("click", (event) => {
    if (event.target === lightbox) {
      closeLightbox();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !lightbox.hidden) {
      closeLightbox();
    }
  });

  zoomableImages.forEach((image) => {
    image.classList.add("zoomable-image");
    image.tabIndex = 0;
    image.setAttribute("role", "button");
    image.setAttribute("aria-label", image.alt ? `${image.alt}. Open larger image` : "Open larger image");

    image.addEventListener("click", () => {
      openLightbox(image);
    });

    image.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        openLightbox(image);
      }
    });
  });
})();
