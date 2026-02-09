import { Citation } from "./interventions";

export interface ParagraphContent {
  type: "paragraph";
  text: string;
  citationIds: string[];
}

export interface BulletListContent {
  type: "bulletList";
  items: string[];
  citationIds: string[];
}

export interface TreatmentItem {
  name: string;
  description: string;
  citationIds: string[];
}

export interface TreatmentListContent {
  type: "treatmentList";
  items: TreatmentItem[];
  citationIds: string[];
}

export interface ResourceItem {
  title: string;
  subtitle: string;
  url: string;
  isPrimary: boolean;
}

export interface ResourceListContent {
  type: "resourceList";
  items: ResourceItem[];
  citationIds: string[];
}

export type SectionContent =
  | ParagraphContent
  | BulletListContent
  | TreatmentListContent
  | ResourceListContent;

export interface Section {
  id: string;
  title: string;
  icon: string;
  color: string;
  content: SectionContent[];
}

export interface BruxismInfoData {
  sections: Section[];
  citations: Citation[];
  disclaimer: string;
}
