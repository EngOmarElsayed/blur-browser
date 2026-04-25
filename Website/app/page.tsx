import { Hero } from "@/components/Hero";
import { HowItWorks } from "@/components/HowItWorks";
import { Performance } from "@/components/Performance";
import { WhoItsFor } from "@/components/WhoItsFor";
import { Features } from "@/components/Features";
import { Roadmap } from "@/components/Roadmap";
import { FinalCTA } from "@/components/FinalCTA";

export default function HomePage() {
  return (
    <>
      <Hero />
      <HowItWorks />
      <Performance />
      <WhoItsFor />
      <Features />
      <Roadmap />
      <FinalCTA />
    </>
  );
}
